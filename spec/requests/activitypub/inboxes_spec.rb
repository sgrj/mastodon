# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ActivityPub Inboxes' do
  let(:remote_account) { nil }

  describe 'POST #create' do
    context 'with signature' do
      let(:remote_account) { Fabricate(:account, domain: 'example.com', protocol: :activitypub) }

      context 'without a named account' do
        subject { post inbox_path, params: {}.to_json, sign_with: remote_account }

        it 'returns http accepted' do
          subject

          expect(response)
            .to have_http_status(202)
        end
      end

      context 'with an excessively large payload' do
        subject { post inbox_path, params: { this: :that, those: :these }.to_json, sign_with: remote_account }

        before { stub_const('ActivityPub::Activity::MAX_JSON_SIZE', 1.byte) }

        it 'returns http content too large' do
          subject

          expect(response)
            .to have_http_status(413)
        end
      end

      context 'with a specific account' do
        subject { post account_inbox_path(account_username: account.username), params: {}.to_json, sign_with: remote_account }

        let(:account) { Fabricate(:account) }

        context 'when account is permanently suspended' do
          before do
            account.suspend!
            account.deletion_request.destroy
          end

          it 'returns http gone' do
            subject

            expect(response)
              .to have_http_status(410)
          end
        end

        context 'when account is temporarily suspended' do
          before { account.suspend! }

          it 'returns http accepted' do
            subject

            expect(response)
              .to have_http_status(202)
          end
        end

        context 'when account is permanently deleted' do
          before do
            account.mark_deleted!
            account.deletion_request.destroy
          end

          it 'returns http gone' do
            subject

            expect(response)
              .to have_http_status(410)
          end
        end

        context 'when account is pending deletion' do
          before do
            account.mark_deleted!
          end

          it 'returns http accepted' do
            subject

            expect(response)
              .to have_http_status(202)
          end
        end
      end
    end

    context 'with Collection-Synchronization header' do
      subject { post inbox_path, params: {}.to_json, headers: { 'Collection-Synchronization' => synchronization_header }, sign_with: remote_account }

      let(:remote_account) { Fabricate(:account, followers_url: 'https://example.com/followers', domain: 'example.com', uri: 'https://example.com/actor', protocol: :activitypub) }
      let(:synchronization_collection) { remote_account.followers_url }
      let(:synchronization_url) { 'https://example.com/followers-for-domain' }
      let(:synchronization_hash) { 'somehash' }
      let(:synchronization_header) { "collectionId=\"#{synchronization_collection}\", digest=\"#{synchronization_hash}\", url=\"#{synchronization_url}\"" }

      before do
        stub_follow_sync_worker
        stub_followers_hash
      end

      context 'with mismatching target collection' do
        let(:synchronization_collection) { 'https://example.com/followers2' }

        it 'does not start a synchronization job' do
          subject

          expect(response)
            .to have_http_status(202)
          expect(ActivityPub::FollowersSynchronizationWorker)
            .to_not have_received(:perform_async)
        end
      end

      context 'with mismatching domain in partial collection attribute' do
        let(:synchronization_url) { 'https://example.org/followers' }

        it 'does not start a synchronization job' do
          subject

          expect(response)
            .to have_http_status(202)
          expect(ActivityPub::FollowersSynchronizationWorker)
            .to_not have_received(:perform_async)
        end
      end

      context 'with matching digest' do
        it 'does not start a synchronization job' do
          subject

          expect(response)
            .to have_http_status(202)
          expect(ActivityPub::FollowersSynchronizationWorker)
            .to_not have_received(:perform_async)
        end
      end

      context 'with mismatching digest' do
        let(:synchronization_hash) { 'wronghash' }

        it 'starts a synchronization job' do
          subject

          expect(response)
            .to have_http_status(202)
          expect(ActivityPub::FollowersSynchronizationWorker)
            .to have_received(:perform_async)
        end
      end

      it 'returns http accepted' do
        subject

        expect(response)
          .to have_http_status(202)
      end

      context 'with OpenTelemetry traces' do
        subject { post inbox_path, params: activity.to_json, headers:, sign_with: remote_account }

        let(:activity) { { id: 'https://example.net/~mallory/87374', type: 'Like' } }

        let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

        let(:span) { instance_double(OpenTelemetry::Trace::Span) }

        before do
          allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)
          allow(span).to receive(:recording?).and_return(true)
          allow(span).to receive(:set_attribute)
        end

        it 'adds attributes to current span' do
          subject

          expect(response).to have_http_status(202)
          expect(span).to have_received(:set_attribute).with('activitypub.activity.id', activity[:id])
          expect(span).to have_received(:set_attribute).with('activitypub.activity.type', activity[:type])
        end
      end

      def stub_follow_sync_worker
        allow(ActivityPub::FollowersSynchronizationWorker)
          .to receive(:perform_async)
          .and_return(nil)
      end

      def stub_followers_hash
        Rails.cache.write("followers_hash:#{remote_account.id}:local", 'somehash') # Populate value to match request
      end
    end

    # Every inbound activity is reported to the Activity Log so the receiving student
    # sees what arrived, before it is handed to the processing worker.
    context 'with Activity Log reporting' do
      let(:remote_account) { Fabricate(:account, domain: 'example.com', uri: 'https://example.com/actor', protocol: :activitypub) }
      let(:account)        { Fabricate(:account) }
      let(:publisher)      { instance_double(ActivityLogPublisher, publish: nil) }

      # Without this the integration session posts as form data, Rack's form parser
      # consumes the body, and the controller sees an empty payload.
      let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

      before { allow(ActivityLogPublisher).to receive(:new).and_return(publisher) }

      def published_event
        captured = nil
        allow(publisher).to receive(:publish) { |event| captured = event }
        yield
        captured
      end

      it 'publishes an inbound event naming the sender and the inbox it arrived at' do
        event = published_event do
          post account_inbox_path(account_username: account.username), params: '{"type":"Follow"}', headers: headers, sign_with: remote_account
        end

        expect(event).to_not be_nil
        expect(event.type).to eq 'inbound'
        expect(event.sender).to eq 'https://example.com/actor'
        expect(event.path).to eq "https://#{Rails.configuration.x.web_domain}/users/#{account.username}/inbox"
        expect(event.data).to eq('type' => 'Follow')
      end

      # The reported path is built from the configured web domain rather than the
      # request host, so that it matches the URIs ActivityLogAudienceHelper matches
      # against.
      it 'reports the path against the configured web domain' do
        event = published_event { post inbox_path, params: '{"type":"Create"}', headers: headers, sign_with: remote_account }

        expect(event.path).to start_with "https://#{Rails.configuration.x.web_domain}/"
        expect(event.path).to end_with '/inbox'
      end

      # Reporting is observability on the federation hot path: if it breaks, Mastodon
      # must still accept the delivery.
      it 'still accepts the delivery when reporting fails' do
        allow(publisher).to receive(:publish).and_raise(Redis::CannotConnectError)

        post inbox_path, params: '{"type":"Create"}', headers: headers, sign_with: remote_account

        expect(response).to have_http_status(202)
      end

      # The fork parsed the body itself and aborted the publish when that raised.
      # Upstream's memoized `parsed_body` returns nil instead, so the event is
      # published with a nil payload and dropped later, when no audience resolves.
      #
      # Deliberately posted without a JSON content type: config/initializers/mime_types.rb
      # makes application/activity+json a synonym of :json, so on Rails 8 a malformed
      # JSON-typed body is rejected by parameter parsing before this controller runs at
      # all. The branch that survives is the one reached here.
      it 'does not reject a delivery whose body could not be parsed' do
        event = published_event { post inbox_path, params: 'not json', sign_with: remote_account }

        expect(response).to have_http_status(202)
        expect(event.data).to be_nil
      end
    end

    context 'without signature' do
      subject { post inbox_path, params: {}.to_json }

      it 'returns http not authorized' do
        subject

        expect(response)
          .to have_http_status(401)
      end

      context 'when sending an unknown account' do
        let(:unknown_actor) do
          {
            actor: 'https://unknown-actor.host',
            object: 'https://unknown-actor.host',
            type: 'Update',
          }
        end
        let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

        it 'returns http accepted' do
          post(inbox_path, params: unknown_actor.to_json, headers:)

          expect(response)
            .to have_http_status(202)
        end
      end
    end
  end
end
