# frozen_string_literal: true

require 'rails_helper'

# The WebFinger Forge lets a student replace the WebFinger document served for their
# own actor, so they can see what breaks (or doesn't) when discovery lies. The point
# of these specs is the last describe block: the override must actually reach the
# public /.well-known/webfinger endpoint that remote instances read.
describe 'WebFinger Forge' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  let(:forged) do
    Oj.dump({ subject: "acct:#{account.username}@example.com", links: [] }, mode: :compat)
  end

  describe 'GET /api/v1/webfinger' do
    it 'requires an authenticated user' do
      get '/api/v1/webfinger'

      expect(response).to have_http_status(422)
    end

    context 'with no override stored' do
      it 'returns the account\'s real WebFinger document' do
        get '/api/v1/webfinger', headers: headers

        expect(response).to have_http_status(200)
        expect(body_as_json[:subject]).to eq account.to_webfinger_s
      end
    end

    context 'with an override stored' do
      before { Fabricate(:web_finger_override, account: account, value: forged) }

      it 'returns the override' do
        get '/api/v1/webfinger', headers: headers

        expect(response).to have_http_status(200)
        expect(Oj.load(response.body, mode: :strict)['subject']).to eq "acct:#{account.username}@example.com"
      end
    end
  end

  describe 'POST /api/v1/webfinger' do
    it 'requires an authenticated user' do
      post '/api/v1/webfinger', params: { value: forged }

      expect(response).to have_http_status(422)
    end

    it 'stores the override for the current account' do
      expect { post '/api/v1/webfinger', params: { value: forged }, headers: headers }
        .to change { WebFingerOverride.where(account_id: account.id).count }.from(0).to(1)

      expect(WebFingerOverride.find_by(account_id: account.id).value).to eq forged
    end

    it 'updates an existing override rather than creating a second one' do
      post '/api/v1/webfinger', params: { value: forged }, headers: headers

      expect { post '/api/v1/webfinger', params: { value: '{"subject":"acct:changed@example.com"}' }, headers: headers }
        .to_not change { WebFingerOverride.where(account_id: account.id).count }.from(1)

      expect(WebFingerOverride.find_by(account_id: account.id).value).to include 'changed'
    end

    # The endpoint claims to validate the payload, but Oj.dump serializes a String
    # rather than parsing it, so it could never fail. Invalid JSON stored here is
    # later served verbatim from /.well-known/webfinger as application/jrd+json.
    it 'rejects a value that is not valid JSON' do
      post '/api/v1/webfinger', params: { value: 'this is not json' }, headers: headers

      expect(response).to have_http_status(422)
      expect(WebFingerOverride.find_by(account_id: account.id)).to be_nil
    end
  end

  describe 'GET /.well-known/webfinger' do
    context 'with no override' do
      it 'serves the normal WebFinger document' do
        get webfinger_url(resource: account.to_webfinger_s)

        expect(response).to have_http_status(200)
        expect(response.media_type).to eq 'application/jrd+json'
        expect(body_as_json[:subject]).to eq account.to_webfinger_s
      end
    end

    context 'with an override' do
      before { Fabricate(:web_finger_override, account: account, value: forged) }

      it 'serves the forged document to remote instances' do
        get webfinger_url(resource: account.to_webfinger_s)

        expect(response).to have_http_status(200)
        expect(response.media_type).to eq 'application/jrd+json'
        expect(Oj.load(response.body, mode: :strict))
          .to eq('subject' => "acct:#{account.username}@example.com", 'links' => [])
      end

      # Upstream sets `expires_in 3.days, public: true` here. The fork removed it,
      # because a cached document would hide the effect of forging one.
      it 'is not publicly cacheable' do
        get webfinger_url(resource: account.to_webfinger_s)

        expect(response.headers['Cache-Control'].to_s).to_not include 'public'
      end
    end

    context 'with an override belonging to a different account' do
      let(:other) { Fabricate(:account, username: 'someone_else') }

      before { Fabricate(:web_finger_override, account: account, value: forged) }

      it 'does not leak the override' do
        get webfinger_url(resource: other.to_webfinger_s)

        expect(body_as_json[:subject]).to eq other.to_webfinger_s
      end
    end
  end
end
