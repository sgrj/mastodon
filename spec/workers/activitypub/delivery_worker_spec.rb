# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::DeliveryWorker do
  include RoutingHelper

  let(:sender) { Fabricate(:account) }
  let(:payload) { 'test' }
  let(:url) { 'https://example.com/api' }

  before do
    allow(sender).to receive(:remote_followers_hash).with(url).and_return('somehash')
    allow(Account).to receive(:find).with(sender.id).and_return(sender)
  end

  describe 'perform' do
    context 'with successful request' do
      before { stub_request(:post, url).to_return(status: 200) }

      it 'performs a request to synchronize collection' do
        subject.perform(payload, sender.id, url, { synchronize_followers: true })

        expect(request_to_url)
          .to have_been_made.once
      end

      context 'when using a numeric ID based scheme' do
        let(:sender) { Fabricate(:account, id_scheme: :numeric_ap_id) }

        it 'performs a request to synchronize collection' do
          subject.perform(payload, sender.id, url, { synchronize_followers: true })

          expect(request_to_url)
            .to have_been_made.once
        end
      end

      def request_to_url
        a_request(:post, url)
          .with(
            headers: {
              'Collection-Synchronization' => <<~VALUES.squish,
                collectionId="#{ActivityPub::TagManager.instance.followers_uri_for(sender)}", digest="somehash", url="#{account_followers_synchronization_url(sender)}"
              VALUES
            }
          )
      end
    end

    context 'with failing request' do
      before { stub_request(:post, url).to_return(status: 500) }

      it 'raises error' do
        expect { subject.perform(payload, sender.id, url) }
          .to raise_error Mastodon::UnexpectedResponseError
      end
    end
  end

  # Every delivery publishes an `outbound` event so the sender sees their own activity,
  # and any failure, in the Activity Log.
  describe 'Activity Log reporting' do
    let(:payload) { { 'type' => 'Follow', 'actor' => 'https://academy.example/users/alice' }.to_json }
    let(:publisher) { instance_double(ActivityLogPublisher, publish: nil) }

    before { allow(ActivityLogPublisher).to receive(:new).and_return(publisher) }

    # Delivery failures propagate (see the rescue in #perform), but the ensure block
    # publishes the Activity Log event first -- which is what these examples assert on.
    def published_events
      captured = []
      allow(publisher).to receive(:publish) { |event| captured << event }
      begin
        yield
      rescue
        nil
      end
      captured
    end

    # #perform sets @failure in two places (perform_request for a non-2xx, and the
    # rescue for a raised error) and publishes from an ensure block, so publishing
    # twice for one attempt is an easy mistake to make. Every example below goes
    # through here, so all of them assert it implicitly.
    def published_event(&block)
      events = published_events(&block)
      expect(events.size).to eq(1), "expected exactly one Activity Log event, got #{events.size}"
      events.first
    end

    it 'publishes an outbound event naming the sender and the inbox' do
      stub_request(:post, url).to_return(status: 200)

      event = published_event { subject.perform(payload, sender.id, url) }

      expect(event).to_not be_nil
      expect(event.type).to eq 'outbound'
      expect(event.sender).to eq ActivityPub::TagManager.instance.uri_for(sender)
      expect(event.path).to eq url
      expect(event.data).to eq('type' => 'Follow', 'actor' => 'https://academy.example/users/alice')
    end

    # The fork hardcoded "https://<web domain>/users/<username>". TagManager is the only
    # thing that knows about v4.7's id_scheme, so it is what decides whether the sender
    # this reports is one ActivityLogAudienceHelper can resolve. These two examples pin
    # why Cluster 4 forces :username_ap_id on every academy account.
    context 'with an account using the username scheme, as academy signup creates' do
      let(:sender) { Fabricate(:account, id_scheme: :username_ap_id) }

      it 'names the sender by an actor URI the audience helper resolves' do
        stub_request(:post, url).to_return(status: 200)

        event = published_event { subject.perform(payload, sender.id, url) }

        expect(event.sender).to eq "https://#{Rails.configuration.x.web_domain}/users/#{sender.username}"
        expect(ActivityLogAudienceHelper.audience(event)).to eq [sender.username]
      end
    end

    context 'with an account using v4.7 default numeric scheme' do
      let(:sender) { Fabricate(:account, id_scheme: :numeric_ap_id) }

      it 'reports the numeric actor URI, which resolves to nobody' do
        stub_request(:post, url).to_return(status: 200)

        event = published_event { subject.perform(payload, sender.id, url) }

        expect(event.sender).to eq "https://#{Rails.configuration.x.web_domain}/ap/users/#{sender.id}"
        expect(ActivityLogAudienceHelper.audience(event)).to be_empty
      end
    end

    it 'records no failure on a successful delivery' do
      stub_request(:post, url).to_return(status: 200)

      event = published_event { subject.perform(payload, sender.id, url) }

      expect(event.as_json['failure']).to be_nil
    end

    it 'records the status code when the inbox rejects the delivery' do
      stub_request(:post, url).to_return(status: 500)

      event = published_event { subject.perform(payload, sender.id, url) }

      expect(event.as_json['failure']).to include '500'
    end

    it 'reports the failure to the Activity Log and still lets Sidekiq see it' do
      stub_request(:post, url).to_return(status: 500)
      published = nil
      allow(publisher).to receive(:publish) { |event| published = event }

      expect { subject.perform(payload, sender.id, url) }
        .to raise_error(Mastodon::UnexpectedResponseError)

      expect(published).to_not be_nil
      expect(published.as_json['failure']).to be_present
    end

    it 'still publishes an event when the request raises' do
      stub_request(:post, url).to_raise(HTTP::ConnectionError.new('connection refused'))

      event = published_event { subject.perform(payload, sender.id, url) }

      expect(event).to_not be_nil
      expect(event.as_json['failure']).to be_present
    end

    # Upstream stops retrying a 410 Gone, and a 401 from an account that is permanently
    # unavailable, without raising -- so the ensure block is the only place a student
    # could ever learn why the activity did not arrive. Showing them that is the whole
    # point of the log, so an unsalvageable response is still a reported failure.
    it 'records an unsalvageable rejection as a failure' do
      stub_request(:post, url).to_return(status: 410)

      event = published_event { subject.perform(payload, sender.id, url) }

      expect(event.as_json['failure']).to include '410'
    end

    it 'does not raise on an unsalvageable rejection' do
      stub_request(:post, url).to_return(status: 410)

      expect { subject.perform(payload, sender.id, url) }.to_not raise_error
    end

    # perform returns early when the inbox is already known to be unavailable, which
    # happens routinely once an instance has been down for a while. The ensure block
    # still runs, so it must not assume perform got as far as loading the account.
    it 'does not blow up when the inbox is already marked unavailable' do
      allow(DeliveryFailureTracker).to receive(:available?).with(url).and_return(false)

      expect { subject.perform(payload, sender.id, url) }.to_not raise_error
    end

    it 'logs nothing at all when the inbox is already marked unavailable' do
      allow(DeliveryFailureTracker).to receive(:available?).with(url).and_return(false)

      events = published_events { subject.perform(payload, sender.id, url) }

      expect(events).to be_empty
    end

    describe 'one attempt, one entry' do
      it 'logs a failed delivery exactly once' do
        stub_request(:post, url).to_return(status: 500)

        events = published_events { subject.perform(payload, sender.id, url) }

        expect(events.size).to eq 1
      end

      it 'logs a successful delivery exactly once' do
        stub_request(:post, url).to_return(status: 200)

        events = published_events { subject.perform(payload, sender.id, url) }

        expect(events.size).to eq 1
      end

      # This worker is retry: 0, but ActivityPub::LowPriorityDeliveryWorker -- which
      # ActivityPub::Forwarder uses -- inherits from it and declares retry: 8. Sidekiq
      # instantiates a fresh worker per attempt, and each attempt is a real HTTP
      # request, so each gets its own Activity Log entry. This pins that deliberately:
      # the log shows what actually went over the wire, rather than collapsing repeated
      # attempts into one.
      it 'logs each retried attempt separately' do
        stub_request(:post, url).to_return(status: 500)

        events = published_events do
          3.times do
            described_class.new.perform(payload, sender.id, url)
          rescue
            nil
          end
        end

        expect(events.size).to eq 3
        expect(events.map { |event| event.as_json['failure'] }).to all(be_present)
      end
    end
  end
end
