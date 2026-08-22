# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::InboxesController, type: :controller do
  let(:remote_account) { nil }

  before do
    allow(controller).to receive(:signed_request_actor).and_return(remote_account)
  end

  describe 'POST #create' do
    context 'with signature' do
      let(:remote_account) { Fabricate(:account, domain: 'example.com', protocol: :activitypub) }

      before do
        post :create, body: '{}'
      end

      it 'returns http accepted' do
        expect(response).to have_http_status(202)
      end

      context 'for a specific account' do
        let(:account) { Fabricate(:account) }

        subject(:response) { post :create, params: { account_username: account.username }, body: '{}' }

        context 'when account is permanently suspended' do
          before do
            account.suspend!
            account.deletion_request.destroy
          end

          it 'returns http gone' do
            expect(response).to have_http_status(410)
          end
        end

        context 'when account is temporarily suspended' do
          before do
            account.suspend!
          end

          it 'returns http accepted' do
            expect(response).to have_http_status(202)
          end
        end
      end
    end

    context 'with Collection-Synchronization header' do
      let(:remote_account)             { Fabricate(:account, followers_url: 'https://example.com/followers', domain: 'example.com', uri: 'https://example.com/actor', protocol: :activitypub) }
      let(:synchronization_collection) { remote_account.followers_url }
      let(:synchronization_url)        { 'https://example.com/followers-for-domain' }
      let(:synchronization_hash)       { 'somehash' }
      let(:synchronization_header)     { "collectionId=\"#{synchronization_collection}\", digest=\"#{synchronization_hash}\", url=\"#{synchronization_url}\"" }

      before do
        allow(ActivityPub::FollowersSynchronizationWorker).to receive(:perform_async).and_return(nil)
        allow_any_instance_of(Account).to receive(:local_followers_hash).and_return('somehash')

        request.headers['Collection-Synchronization'] = synchronization_header
        post :create, body: '{}'
      end

      context 'with mismatching target collection' do
        let(:synchronization_collection) { 'https://example.com/followers2' }

        it 'does not start a synchronization job' do
          expect(ActivityPub::FollowersSynchronizationWorker).not_to have_received(:perform_async)
        end
      end

      context 'with mismatching domain in partial collection attribute' do
        let(:synchronization_url) { 'https://example.org/followers' }

        it 'does not start a synchronization job' do
          expect(ActivityPub::FollowersSynchronizationWorker).not_to have_received(:perform_async)
        end
      end

      context 'with matching digest' do
        it 'does not start a synchronization job' do
          expect(ActivityPub::FollowersSynchronizationWorker).not_to have_received(:perform_async)
        end
      end

      context 'with mismatching digest' do
        let(:synchronization_hash) { 'wronghash' }

        it 'starts a synchronization job' do
          expect(ActivityPub::FollowersSynchronizationWorker).to have_received(:perform_async)
        end
      end

      it 'returns http accepted' do
        expect(response).to have_http_status(202)
      end
    end

    context 'without signature' do
      before do
        post :create, body: '{}'
      end

      it 'returns http not authorized' do
        expect(response).to have_http_status(401)
      end
    end
  end

  # Every inbound activity is reported to the Activity Log so the receiving student
  # sees what arrived, before it is handed to the processing worker.
  describe 'Activity Log reporting' do
    let(:remote_account) { Fabricate(:account, domain: 'example.com', uri: 'https://example.com/actor', protocol: :activitypub) }
    let(:account)        { Fabricate(:account) }

    def published_event
      captured = nil
      allow_any_instance_of(ActivityLogPublisher).to receive(:publish) { |_, event| captured = event }
      yield
      captured
    end

    it 'publishes an inbound event naming the sender and the inbox it arrived at' do
      event = published_event do
        post :create, params: { account_username: account.username }, body: '{"type":"Follow"}'
      end

      expect(event).to_not be_nil
      expect(event.type).to eq 'inbound'
      expect(event.sender).to eq 'https://example.com/actor'
      expect(event.path).to eq "https://#{Rails.configuration.x.web_domain}/users/#{account.username}/inbox"
      expect(event.data).to eq('type' => 'Follow')
    end

    # The reported path is built from the configured web domain rather than the request
    # host, so that it matches the URIs ActivityLogAudienceHelper matches against.
    it 'reports the path against the configured web domain' do
      event = published_event { post :create, body: '{"type":"Create"}' }

      expect(event.path).to start_with "https://#{Rails.configuration.x.web_domain}/"
      expect(event.path).to end_with '/inbox'
    end

    # Reporting is observability on the federation hot path: if it breaks, Mastodon
    # must still accept the delivery.
    it 'still accepts the delivery when reporting fails' do
      allow_any_instance_of(ActivityLogPublisher).to receive(:publish).and_raise(Redis::CannotConnectError)

      post :create, body: '{"type":"Create"}'

      expect(response).to have_http_status(202)
    end

    it 'does not reject a delivery whose body is not valid JSON' do
      allow_any_instance_of(ActivityLogPublisher).to receive(:publish)

      post :create, body: 'not json'

      expect(response).to have_http_status(202)
    end
  end
end
