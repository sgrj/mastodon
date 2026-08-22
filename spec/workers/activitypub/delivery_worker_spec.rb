# frozen_string_literal: true

require 'rails_helper'

describe ActivityPub::DeliveryWorker do
  include RoutingHelper

  subject { described_class.new }

  let(:sender)  { Fabricate(:account) }
  let(:payload) { 'test' }

  before do
    allow_any_instance_of(Account).to receive(:remote_followers_hash).with('https://example.com/api').and_return('somehash')
  end

  describe 'perform' do
    it 'performs a request' do
      stub_request(:post, 'https://example.com/api').to_return(status: 200)
      subject.perform(payload, sender.id, 'https://example.com/api', { synchronize_followers: true })
      expect(a_request(:post, 'https://example.com/api').with(headers: { 'Collection-Synchronization' => "collectionId=\"#{account_followers_url(sender)}\", digest=\"somehash\", url=\"#{account_followers_synchronization_url(sender)}\"" })).to have_been_made.once
    end

    it 'raises when request fails' do
      stub_request(:post, 'https://example.com/api').to_return(status: 500)
      expect { subject.perform(payload, sender.id, 'https://example.com/api') }.to raise_error Mastodon::UnexpectedResponseError
    end
  end

  # Every delivery publishes an `outbound` event so the sender sees their own activity,
  # and any failure, in the Activity Log.
  describe 'Activity Log reporting' do
    let(:payload) { Oj.dump({ 'type' => 'Follow', 'actor' => 'https://academy.example/users/alice' }) }

    # Delivery failures propagate (see the rescue in #perform), but the ensure block
    # publishes the Activity Log event first -- which is what these examples assert on.
    def published_events
      captured = []
      allow_any_instance_of(ActivityLogPublisher).to receive(:publish) { |_, event| captured << event }
      begin
        yield
      rescue StandardError
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
      stub_request(:post, 'https://example.com/api').to_return(status: 200)

      event = published_event { subject.perform(payload, sender.id, 'https://example.com/api') }

      expect(event).to_not be_nil
      expect(event.type).to eq 'outbound'
      expect(event.sender).to eq "https://#{Rails.configuration.x.web_domain}/users/#{sender.username}"
      expect(event.path).to eq 'https://example.com/api'
      expect(event.data).to eq('type' => 'Follow', 'actor' => 'https://academy.example/users/alice')
    end

    it 'records no failure on a successful delivery' do
      stub_request(:post, 'https://example.com/api').to_return(status: 200)

      event = published_event { subject.perform(payload, sender.id, 'https://example.com/api') }

      expect(event.as_json['failure']).to be_nil
    end

    it 'records the status code when the inbox rejects the delivery' do
      stub_request(:post, 'https://example.com/api').to_return(status: 500)

      event = published_event { subject.perform(payload, sender.id, 'https://example.com/api') }

      expect(event.as_json['failure']).to include '500'
    end

    it 'reports the failure to the Activity Log and still lets Sidekiq see it' do
      stub_request(:post, 'https://example.com/api').to_return(status: 500)
      published = nil
      allow_any_instance_of(ActivityLogPublisher).to receive(:publish) { |_, event| published = event }

      expect { subject.perform(payload, sender.id, 'https://example.com/api') }
        .to raise_error(Mastodon::UnexpectedResponseError)

      expect(published).to_not be_nil
      expect(published.as_json['failure']).to be_present
    end

    it 'still publishes an event when the request raises' do
      stub_request(:post, 'https://example.com/api').to_raise(HTTP::ConnectionError.new('connection refused'))

      event = published_event { subject.perform(payload, sender.id, 'https://example.com/api') }

      expect(event).to_not be_nil
      expect(event.as_json['failure']).to be_present
    end

    # perform returns early when the inbox is already known to be unavailable, which
    # happens routinely once an instance has been down for a while. The ensure block
    # still runs, so it must not assume perform got as far as loading the account.
    it 'does not blow up when the inbox is already marked unavailable' do
      allow(DeliveryFailureTracker).to receive(:available?).with('https://example.com/api').and_return(false)

      expect { subject.perform(payload, sender.id, 'https://example.com/api') }.to_not raise_error
    end

    it 'logs nothing at all when the inbox is already marked unavailable' do
      allow(DeliveryFailureTracker).to receive(:available?).with('https://example.com/api').and_return(false)

      events = published_events { subject.perform(payload, sender.id, 'https://example.com/api') }

      expect(events).to be_empty
    end

    describe 'one attempt, one entry' do
      it 'logs a failed delivery exactly once' do
        stub_request(:post, 'https://example.com/api').to_return(status: 500)

        events = published_events { subject.perform(payload, sender.id, 'https://example.com/api') }

        expect(events.size).to eq 1
      end

      it 'logs a successful delivery exactly once' do
        stub_request(:post, 'https://example.com/api').to_return(status: 200)

        events = published_events { subject.perform(payload, sender.id, 'https://example.com/api') }

        expect(events.size).to eq 1
      end

      # Now that delivery errors propagate, Sidekiq retries them -- 8 times for
      # ActivityPub::LowPriorityDeliveryWorker, which is what ActivityPub::Forwarder
      # uses. Sidekiq instantiates a fresh worker per attempt, and each attempt is a
      # real HTTP request, so each gets its own Activity Log entry. This pins that
      # deliberately: the log shows what actually went over the wire, rather than
      # collapsing repeated attempts into one.
      it 'logs each retried attempt separately' do
        stub_request(:post, 'https://example.com/api').to_return(status: 500)

        events = published_events do
          3.times do
            begin
              described_class.new.perform(payload, sender.id, 'https://example.com/api')
            rescue StandardError
              nil
            end
          end
        end

        expect(events.size).to eq 3
        expect(events.map { |event| event.as_json['failure'] }).to all(be_present)
      end
    end
  end
end
