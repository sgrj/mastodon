# frozen_string_literal: true

require 'rails_helper'

# The browser holds open an EventSource against /api/v1/activity_log for the whole
# session (see app/javascript/mastodon/containers/mastodon.js). The endpoint hijacks
# the Rack socket and hands it to ActivityLogger, keyed by the account's username --
# which is the key ActivityLogAudienceHelper resolves to.
describe 'Activity Log stream' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  describe 'GET /api/v1/activity_log' do
    it 'requires an authenticated user' do
      get '/api/v1/activity_log'

      expect(response).to have_http_status(422)
    end

    it 'responds as an event stream' do
      get '/api/v1/activity_log', headers: headers

      expect(response).to have_http_status(200)
      expect(response.headers['Content-Type']).to include 'text/event-stream'
    end

    # Set so Rack does not compute an ETag, which would buffer the response and delay
    # the first event.
    it 'sets Last-Modified so the response is not buffered for an ETag' do
      get '/api/v1/activity_log', headers: headers

      expect(response.headers['Last-Modified']).to be_present
    end

    it 'registers the hijacked socket against the account username' do
      get '/api/v1/activity_log', headers: headers

      hijack = response.headers['rack.hijack']
      expect(hijack).to be_a(Proc)

      expect { hijack.call(StringIO.new) }
        .to change { ActivityLogger.send(:class_variable_get, :@@loggers)[account.username].size }
        .from(0).to(1)
    end

    it 'delivers an event published for that account to the hijacked socket' do
      get '/api/v1/activity_log', headers: headers

      io = StringIO.new
      response.headers['rack.hijack'].call(io)

      ActivityLogger.log(
        account.username,
        ActivityLogEvent.new('inbound', 'https://remote.example/users/alice', "https://#{Rails.configuration.x.web_domain}/users/#{account.username}/inbox", { 'type' => 'Follow' })
      )

      expect(io.string).to include 'Follow'
    end
  end
end
