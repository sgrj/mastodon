# frozen_string_literal: true

require 'rails_helper'

# The ActivityPub Explorer fetches arbitrary remote JSON-LD documents on the student's
# behalf, signed with the instance actor's key, so they can inspect actors and objects
# that would otherwise require authorized fetch.
#
# #show hijacks the Rack socket and answers from a bare thread, so it is not reachable
# through Rack::Test. The pieces that carry the logic are tested directly instead.
RSpec.describe Api::V1::JsonLdController, type: :controller do
  subject { described_class.new }

  def faraday_response(status:, headers: {})
    instance_double(Faraday::Response, status: status, headers: headers)
  end

  describe '#get_redirect_location' do
    let(:host) { 'https://remote.example' }

    it 'follows a 301' do
      response = faraday_response(status: 301, headers: { 'location' => 'https://remote.example/actor' })

      expect(subject.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor'
    end

    it 'follows a 302' do
      response = faraday_response(status: 302, headers: { 'location' => 'https://remote.example/actor' })

      expect(subject.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor'
    end

    it 'resolves a relative redirect against the original host' do
      response = faraday_response(status: 302, headers: { 'location' => '/actor' })

      expect(subject.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor'
    end

    # https://www.w3.org/TR/json-ld11/#alternate-document-location — a server may serve
    # HTML at the canonical URL and point at the JSON-LD via a Link header.
    it 'follows the JSON-LD alternate document location on a 200' do
      response = faraday_response(
        status: 200,
        headers: { 'link' => '<https://remote.example/actor.jsonld>; rel="alternate"; type="application/ld+json"' }
      )

      expect(subject.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor.jsonld'
    end

    it 'matches the alternate link header case-insensitively' do
      response = faraday_response(
        status: 200,
        headers: { 'link' => '<https://remote.example/a.jsonld>; REL="alternate"; TYPE="application/LD+JSON"' }
      )

      expect(subject.send(:get_redirect_location, response, host)).to eq 'https://remote.example/a.jsonld'
    end

    it 'ignores a link header advertising some other relation' do
      response = faraday_response(
        status: 200,
        headers: { 'link' => '<https://remote.example/next>; rel="next"; type="application/ld+json"' }
      )

      expect(subject.send(:get_redirect_location, response, host)).to be_nil
    end

    it 'returns nil for a plain 200' do
      expect(subject.send(:get_redirect_location, faraday_response(status: 200), host)).to be_nil
    end

    it 'returns nil for an error response' do
      expect(subject.send(:get_redirect_location, faraday_response(status: 404), host)).to be_nil
    end
  end

  describe '#follow_redirects' do
    let(:url) { 'https://remote.example/actor' }

    it 'returns the first non-redirecting response' do
      final = faraday_response(status: 200)
      conn  = instance_double(Faraday::Connection)

      allow(conn).to receive(:get).with(url, nil, anything)
        .and_return(faraday_response(status: 302, headers: { 'location' => 'https://remote.example/final' }))
      allow(conn).to receive(:get).with('https://remote.example/final', nil, anything).and_return(final)

      expect(subject.send(:follow_redirects, conn, url)).to eq final
    end

    # The loop used to decrement a counter it never checked, so a redirect cycle span
    # forever inside a detached thread, hammering the remote host.
    it 'gives up on a redirect cycle instead of looping forever' do
      conn = instance_double(Faraday::Connection)
      allow(conn).to receive(:get).and_return(
        faraday_response(status: 302, headers: { 'location' => url })
      )

      Timeout.timeout(5) { subject.send(:follow_redirects, conn, url) }

      expect(conn).to have_received(:get).at_most(described_class::MAX_REDIRECTS + 1).times
    end
  end

  describe '#signed_headers' do
    it 'asks for JRD when fetching a WebFinger document, without signing' do
      headers = subject.send(:signed_headers, 'https://remote.example/.well-known/webfinger?resource=acct:a@b')

      expect(headers[:Accept]).to eq 'application/jrd+json'
      expect(headers).to_not have_key(:Signature)
    end

    it 'asks for ActivityPub JSON otherwise' do
      headers = subject.send(:signed_headers, 'https://remote.example/users/alice')

      expect(headers[:Accept]).to include 'application/activity+json'
      expect(headers[:Host]).to eq 'remote.example'
      expect(headers[:Date]).to be_present
      expect(headers[:'User-Agent']).to eq Mastodon::Version.user_agent
    end

    it 'does not leak the pseudo-header used to build the signature' do
      headers = subject.send(:signed_headers, 'https://remote.example/users/alice')

      expect(headers).to_not have_key(described_class::REQUEST_TARGET)
    end

    it 'signs as the instance actor with a signature that verifies' do
      url     = 'https://remote.example/users/alice'
      headers = subject.send(:signed_headers, url)
      account = Account.representative

      expect(headers[:Signature]).to include "keyId=\"#{ActivityPub::TagManager.instance.key_uri_for(account)}\""
      expect(headers[:Signature]).to include 'algorithm="rsa-sha256"'

      signature = headers[:Signature][/signature="([^"]+)"/, 1]
      signed_string = [
        "date: #{headers[:Date]}",
        "host: #{headers[:Host]}",
        "accept: #{headers[:Accept]}",
        "(request-target): get /users/alice",
      ].join("\n")

      expect(
        account.keypair.public_key.verify(
          OpenSSL::Digest.new('SHA256'), Base64.decode64(signature), signed_string
        )
      ).to be true
    end
  end
end
