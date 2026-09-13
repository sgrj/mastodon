# frozen_string_literal: true

require 'rails_helper'

# The ActivityPub Explorer fetches arbitrary remote documents on the student's behalf,
# signed with the instance actor's key, so they can inspect actors and objects that
# would otherwise require authorized fetch -- and so they can see a 404, an HTML page
# or a redirect for what it is.
#
# #show hijacks the Rack socket and answers from a bare thread, so it is not reachable
# through Rack::Test. The pieces that carry the logic are exercised directly instead;
# what *is* reachable (routing, authentication, parameter validation) is covered by
# spec/requests/activitypub_explorer_spec.rb.
RSpec.describe Api::V1::JsonLdController do
  let(:explorer) { described_class.new }

  def proxied(status:, headers: {}, body: '')
    described_class::ProxiedResponse.new(status, HTTP::Headers.coerce(headers), body)
  end

  # The signature is applied by Request's own http.rb middleware, so the only honest
  # way to assert it is to read it off the request that actually went out.
  def capture_request(url, status: 200, body: '{}', content_type: 'application/activity+json')
    stub_request(:get, url).to_return do |request|
      @outgoing = request
      { status: status, body: body, headers: { 'Content-Type' => content_type } }
    end
  end

  attr_reader :outgoing

  def signature_params
    outgoing.headers.fetch('Signature').scan(/(\w+)="([^"]*)"/).to_h
  end

  # draft-cavage-http-signatures-12: the signed string is the covered headers in the
  # order the `headers` parameter lists them, one `name: value` per line.
  def signed_string
    signature_params.fetch('headers').split.map do |name|
      if name == '(request-target)'
        "(request-target): get #{outgoing.uri.path}"
      else
        "#{name}: #{outgoing.headers.fetch(name.split('-').map(&:capitalize).join('-'))}"
      end
    end.join("\n")
  end

  describe '#get_redirect_location' do
    let(:host) { 'https://remote.example' }

    it 'follows a 301' do
      response = proxied(status: 301, headers: { 'Location' => 'https://remote.example/actor' })

      expect(explorer.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor'
    end

    it 'follows a 302' do
      response = proxied(status: 302, headers: { 'Location' => 'https://remote.example/actor' })

      expect(explorer.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor'
    end

    it 'resolves a relative redirect against the original host' do
      response = proxied(status: 302, headers: { 'Location' => '/actor' })

      expect(explorer.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor'
    end

    # https://www.w3.org/TR/json-ld11/#alternate-document-location -- a server may serve
    # HTML at the canonical URL and point at the JSON-LD via a Link header.
    it 'follows the JSON-LD alternate document location on a 200' do
      response = proxied(
        status: 200,
        headers: { 'Link' => '<https://remote.example/actor.jsonld>; rel="alternate"; type="application/ld+json"' }
      )

      expect(explorer.send(:get_redirect_location, response, host)).to eq 'https://remote.example/actor.jsonld'
    end

    it 'matches the alternate link header case-insensitively' do
      response = proxied(
        status: 200,
        headers: { 'Link' => '<https://remote.example/a.jsonld>; REL="alternate"; TYPE="application/LD+JSON"' }
      )

      expect(explorer.send(:get_redirect_location, response, host)).to eq 'https://remote.example/a.jsonld'
    end

    # http.rb keeps repeated headers as separate values rather than joining them the way
    # Faraday did, so a server that sends one Link header per relation must still
    # resolve to the alternate one.
    it 'finds the alternate location among several Link headers' do
      headers = HTTP::Headers.new
      headers.add('Link', '<https://remote.example/next>; rel="next"')
      headers.add('Link', '<https://remote.example/a.jsonld>; rel="alternate"; type="application/ld+json"')
      response = described_class::ProxiedResponse.new(200, headers, '')

      expect(explorer.send(:get_redirect_location, response, host)).to eq 'https://remote.example/a.jsonld'
    end

    it 'ignores a link header advertising some other relation' do
      response = proxied(
        status: 200,
        headers: { 'Link' => '<https://remote.example/next>; rel="next"; type="application/ld+json"' }
      )

      expect(explorer.send(:get_redirect_location, response, host)).to be_nil
    end

    it 'returns nil for a plain 200' do
      expect(explorer.send(:get_redirect_location, proxied(status: 200), host)).to be_nil
    end

    it 'returns nil for an error response' do
      expect(explorer.send(:get_redirect_location, proxied(status: 404), host)).to be_nil
    end
  end

  describe '#follow_redirects' do
    let(:url) { 'https://remote.example/actor' }

    it 'returns the first non-redirecting response' do
      final = proxied(status: 200, body: '{}')

      allow(explorer).to receive(:fetch).with(url)
        .and_return(proxied(status: 302, headers: { 'Location' => 'https://remote.example/final' }))
      allow(explorer).to receive(:fetch).with('https://remote.example/final').and_return(final)

      expect(explorer.send(:follow_redirects, url)).to eq final
    end

    # Everything the Explorer exists for lives on this path: an error response is a
    # result to show, not a failure to swallow.
    it 'returns an error response unchanged' do
      not_found = proxied(status: 404, headers: { 'Content-Type' => 'text/html' }, body: '<h1>nope</h1>')
      allow(explorer).to receive(:fetch).with(url).and_return(not_found)

      expect(explorer.send(:follow_redirects, url)).to eq not_found
    end

    # The fork assembled the base for a relative redirect as scheme + host, which drops
    # a non-default port: every relative redirect from a server not on 80/443 went to
    # the wrong place (observed live against a probe server on :4567).
    it 'keeps a non-default port when resolving a relative redirect' do
      ported = 'http://remote.example:4567/start'
      final = proxied(status: 200, body: '{}')

      allow(explorer).to receive(:fetch).with(ported)
        .and_return(proxied(status: 302, headers: { 'Location' => '/final' }))
      allow(explorer).to receive(:fetch).with('http://remote.example:4567/final').and_return(final)

      expect(explorer.send(:follow_redirects, ported)).to eq final
    end

    # A chain that crosses hosts resolves each relative location against the URL that
    # issued it, not against the one the student typed.
    it 'resolves a relative redirect against the host that issued it' do
      final = proxied(status: 200, body: '{}')

      allow(explorer).to receive(:fetch).with(url)
        .and_return(proxied(status: 302, headers: { 'Location' => 'https://elsewhere.example/actor' }))
      allow(explorer).to receive(:fetch).with('https://elsewhere.example/actor')
        .and_return(proxied(status: 302, headers: { 'Location' => '/canonical' }))
      allow(explorer).to receive(:fetch).with('https://elsewhere.example/canonical').and_return(final)

      expect(explorer.send(:follow_redirects, url)).to eq final
    end

    # The loop used to decrement a counter it never checked, so a redirect cycle spun
    # forever inside a detached thread, hammering the remote host.
    it 'gives up on a redirect cycle instead of looping forever' do
      allow(explorer).to receive(:fetch).and_return(
        proxied(status: 302, headers: { 'Location' => url })
      )

      Timeout.timeout(5) { explorer.send(:follow_redirects, url) }

      expect(explorer).to have_received(:fetch).at_most(described_class::MAX_REDIRECTS + 1).times
    end
  end

  describe '#build_request' do
    it 'asks for JRD when fetching a WebFinger document, without signing' do
      request = explorer.send(:build_request, 'https://remote.example/.well-known/webfinger?resource=acct:a@b')

      expect(request.headers['Accept']).to eq 'application/jrd+json'
      expect(request.signing_keypair).to be_nil
    end

    it 'asks for ActivityPub JSON otherwise' do
      request = explorer.send(:build_request, 'https://remote.example/users/alice')

      expect(request.headers['Accept']).to include 'application/activity+json'
      expect(request.headers['Host']).to eq 'remote.example'
      expect(request.headers['Date']).to be_present
      expect(request.headers['User-Agent']).to eq Mastodon::Version.user_agent
    end

    it 'signs as the instance actor' do
      request = explorer.send(:build_request, 'https://remote.example/users/alice')

      expect(request.signing_keypair.account).to eq Account.representative
      expect(request.signing_keypair.type).to eq 'rsa'
    end
  end

  describe '#fetch' do
    let(:url) { 'https://remote.example/users/alice' }

    it 'returns the status, headers and body of a successful fetch' do
      capture_request(url, body: '{"type":"Person"}')

      result = explorer.send(:fetch, url)

      expect(result.status).to eq 200
      expect(result.headers['Content-Type']).to eq 'application/activity+json'
      expect(result.body).to eq '{"type":"Person"}'
    end

    # JsonLdHelper#fetch_resource_without_id_validation would turn this into nil. The
    # Explorer has to hand it to the student verbatim.
    it 'returns a 404 and its body rather than raising' do
      capture_request(url, status: 404, body: '<h1>Not Found</h1>', content_type: 'text/html')

      result = explorer.send(:fetch, url)

      expect(result.status).to eq 404
      expect(result.headers['Content-Type']).to eq 'text/html'
      expect(result.body).to eq '<h1>Not Found</h1>'
    end

    it 'relays a body up to the 1 MB ceiling' do
      body = 'x' * (1.megabyte - 1)
      capture_request(url, body: body)

      result = explorer.send(:fetch, url)

      expect(result.status).to eq 200
      expect(result.body.bytesize).to eq body.bytesize
    end

    # Not truncated: half a JSON document reads as a malformed one, which is a worse
    # lesson than an explicit refusal.
    it 'refuses a body over the ceiling and explains why' do
      capture_request(url, body: 'x' * (1.megabyte + 1))

      result = explorer.send(:fetch, url)

      expect(result.status).to eq 502
      expect(result.body).to include 'refused to relay response'
      expect(result.body).to include 'MAX_JSON_SIZE'
      expect(result.body).to_not include 'xxxx'
    end

    it 'rejects an oversized body on Content-Length without reading it' do
      stub_request(:get, url).to_return(
        status: 200,
        body: 'x' * 32,
        headers: { 'Content-Type' => 'application/activity+json', 'Content-Length' => (1.megabyte + 1).to_s }
      )

      expect(explorer.send(:fetch, url).status).to eq 502
    end

    it 'does not follow redirects itself, so the Explorer can bound the chain' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://remote.example/final' })

      expect(explorer.send(:fetch, url).status).to eq 302
      expect(a_request(:get, 'https://remote.example/final')).to_not have_been_made
    end

    it 'sends a draft-cavage signature that verifies against the instance actor key' do
      capture_request(url)

      explorer.send(:fetch, url)

      keypair = Account.representative.keypair(type: :rsa)

      expect(signature_params.fetch('keyId')).to eq keypair.full_uri
      expect(signature_params.fetch('algorithm')).to eq 'rsa-sha256'
      expect(signature_params.fetch('headers')).to include '(request-target)'
      expect(
        keypair.keypair.public_key.verify(
          OpenSSL::Digest.new('SHA256'),
          Base64.decode64(signature_params.fetch('signature')),
          signed_string
        )
      ).to be true
    end

    it 'does not sign a WebFinger fetch' do
      webfinger_url = 'https://remote.example/.well-known/webfinger?resource=acct:alice@remote.example'
      capture_request(webfinger_url, content_type: 'application/jrd+json')

      explorer.send(:fetch, webfinger_url)

      expect(outgoing.headers).to_not have_key('Signature')
      expect(outgoing.headers['Accept']).to eq 'application/jrd+json'
    end
  end
end
