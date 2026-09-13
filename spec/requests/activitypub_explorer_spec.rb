# frozen_string_literal: true

require 'rails_helper'

# `Api::V1::JsonLdController#show` hijacks the Rack socket and writes a raw HTTP
# response from a detached thread, which Rack::Test cannot represent -- there is no
# `rack.hijack` in its environment. What these examples pin is everything that happens
# *before* the hijack, which is precisely the part that has to be able to render:
# routing, authentication, and the URL check.
#
# The signed fetch, the redirect chain and the raw write are covered in
# spec/controllers/api/v1/json_ld_controller_spec.rb and by hand against a real Puma
# (see PORTING.md, Cluster 7).
RSpec.describe 'ActivityPub Explorer' do
  include_context 'with API authentication', oauth_scopes: 'read'

  describe 'GET /api/v1/json_ld' do
    it 'requires an authenticated user' do
      get '/api/v1/json_ld', params: { url: 'https://remote.example/users/alice' }

      expect(response).to have_http_status(422)
      expect(response.parsed_body[:error]).to eq 'This method requires an authenticated user'
    end

    it 'rejects a missing url before hijacking the socket' do
      get '/api/v1/json_ld', headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body[:error]).to eq 'Missing required parameter: url'
    end

    it 'rejects a url that is not fetchable over http' do
      get '/api/v1/json_ld', params: { url: 'file:///etc/passwd' }, headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body[:error]).to eq 'Not a fetchable http(s) URL: file:///etc/passwd'
    end
  end
end
