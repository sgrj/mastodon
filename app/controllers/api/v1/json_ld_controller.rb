# frozen_string_literal: true

# Backs the ActivityPub Explorer: fetches whatever URL the student pastes, signed as
# the instance actor, and hands the raw HTTP response straight back to the browser --
# status, Content-Type and body, untouched.
#
# Nothing here parses or validates the result. A 404, an HTML page, a redirect or a
# `.well-known` JRD document are all things the Explorer exists to show, so
# `JsonLdHelper#fetch_resource_without_id_validation` (which returns parsed JSON only
# for a 200 with an ActivityPub content type, and nil for everything else) is exactly
# the wrong tool.
#
# Fetching arbitrary URLs on behalf of a logged-in student -- private addresses
# included -- is a deliberate SSRF and the point of the exercise. See TESTING.md.
class Api::V1::JsonLdController < Api::BaseController
  include ActionController::Live

  MAX_REDIRECTS = 5

  ACTIVITYPUB_ACCEPT = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
  WEBFINGER_ACCEPT = 'application/jrd+json'

  # What is carried out of `Request#perform`'s block. The response object itself is not
  # usable afterwards -- `perform` drains and closes the connection in an ensure -- so
  # the status, the headers and the whole body have to be read while it is still open.
  ProxiedResponse = Struct.new(:status, :headers, :body)

  # The remote body is read into memory in a detached thread, so it needs a ceiling.
  # 1 MB is Mastodon's own: it is what `body_with_limit` defaults to, and what
  # `ActivityPub::Activity::MAX_JSON_SIZE` allows an inbox to accept. Sharing the
  # number keeps the Explorer honest -- anything it will not show a student is also
  # something their instance would have refused.
  MAX_BODY_SIZE = 1.megabyte

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  before_action :require_user!

  def show
    url = params[:url]

    # Checked *before* the socket is hijacked. Afterwards Rails can no longer write
    # anything to this client, so `rescue_from` would have nowhere to render.
    raise ArgumentError, 'Missing required parameter: url' if url.blank?
    raise ArgumentError, "Not a fetchable http(s) URL: #{url}" unless Request.valid_url?(url)

    # Full hijack. Rack 3 has the callable return the IO; Puma 8 also still sets
    # `rack.hijack_io`, which is what the fork read. Verified against puma 8.0.2.
    io = request.env['rack.hijack'].call || request.env['rack.hijack_io']

    # A hand-spawned thread has no Rails execution context of its own: the database
    # connection `Account.representative` leases would be held until the Puma worker
    # exits, and autoloading from it is not safe. Same reasoning as
    # `ActivityLogSubscriber` -- see Surprise 28 in PORTING.md.
    Thread.new do
      Rails.application.executor.wrap { write_response(io, follow_redirects(url)) }
    rescue => e
      # Nothing else reports a failure in a detached thread.
      Rails.logger.error { "ActivityPub Explorer: #{e.class}: #{e.message} on #{url}" }
      write_error(io)
    ensure
      close_quietly(io)
    end
  end

  private

  def write_response(io, proxied)
    io.write("HTTP/1.1 #{proxied.status} #{Rack::Utils::HTTP_STATUS_CODES.fetch(proxied.status, '')}\r\n")
    io.write("Content-Type: #{proxied.headers['Content-Type']}\r\n") if proxied.headers['Content-Type'].present?
    io.write("Content-Length: #{proxied.body.bytesize}\r\n")
    io.write("Access-Control-Allow-Origin: *\r\n")
    io.write("Connection: close\r\n")
    io.write("\r\n")
    io.write(proxied.body)
  end

  def write_error(io)
    io.write("HTTP/1.1 500 Internal Server Error\r\n")
    io.write("Access-Control-Allow-Origin: *\r\n")
    io.write("Connection: close\r\n")
    io.write("\r\n")
  rescue IOError, SystemCallError
    nil
  end

  def close_quietly(io)
    io.close
  rescue IOError, SystemCallError
    nil
  end

  # Signing is `Request`'s job, not ours: it owns the draft-cavage signature, the
  # RFC 9421 double-knock, and the `keypairs` table 4.7 moved local private keys into.
  def build_request(url)
    # `follow: false` because the redirect chain is followed here instead: HTTP.rb
    # cannot see the JSON-LD alternate document location, which is a Link header on a
    # 200 rather than a redirect at all, and its max_hops is 3 rather than the fork's 5.
    #
    # `allow_local: true` keeps the SSRF deliberate. Without it `Request::Socket`
    # refuses every private address outside development, and half of what a student is
    # asked to fetch in a workshop lives on the lab network.
    request = Request.new(:get, url, allow_local: true, follow: false)

    if webfinger_url?(url)
      # WebFinger is unauthenticated everywhere; a signature on it would only muddle
      # the lesson.
      request.add_headers('Accept' => WEBFINGER_ACCEPT)
    else
      request.on_behalf_of(Account.representative)
      request.add_headers('Accept' => ACTIVITYPUB_ACCEPT)
    end

    request
  end

  def webfinger_url?(url)
    url.include?('.well-known')
  end

  def fetch(url)
    build_request(url).perform do |response|
      ProxiedResponse.new(response.code, response.headers, response.body_with_limit(MAX_BODY_SIZE))
    rescue Mastodon::LengthValidationError => e
      # Deliberately not truncated. Half a JSON document teaches nothing and looks like
      # a malformed one, so a student who fetches something enormous is told why
      # instead. `body_with_limit` checks Content-Length before reading, so an
      # oversized response that advertises its size honestly costs us nothing.
      ProxiedResponse.new(
        502,
        { 'Content-Type' => 'text/plain; charset=utf-8' },
        # Diagnostic output for a developer-facing tool, deliberately not localised: it
        # names Ruby constants and is read next to the raw HTTP the Explorer exists to
        # show. Routing debug text through I18n would only hand it to translators.
        [
          'explorer: refused to relay response',
          "reason:   #{e.message}",
          "limit:    #{MAX_BODY_SIZE} bytes, shared with ActivityPub::Activity::MAX_JSON_SIZE",
          'note:     too large to explore here means too large to federate',
          '',
        ].join("\n")
      )
    end
  end

  def get_redirect_location(api_response, host)
    location = if [301, 302].include?(api_response.status)
                 api_response.headers['Location']
               elsif api_response.status == 200
                 # For JSON-LD, the actual document might be at an alternate location
                 # specified by the Link header; see
                 # https://www.w3.org/TR/json-ld11/#alternate-document-location
                 api_response.headers.get('Link').join(', ')[%r{<([^>]+)>;\s*rel="alternate";\s*type="application/ld\+json"}i, 1]
               end

    # Return nil if no location found
    return nil if location.nil?

    # Prepend host if location is relative and host is provided
    if host && location.start_with?('/')
      host + location
    else
      location
    end
  end

  # Follows ordinary redirects as well as the JSON-LD alternate document location.
  # Bounded: a redirect cycle would otherwise spin forever inside a detached thread,
  # hammering the remote host.
  def follow_redirects(url)
    api_response = fetch(url)

    MAX_REDIRECTS.times do
      # `site` is scheme + authority, so it keeps a non-default port -- the fork built
      # this by hand out of scheme and host and lost it, which broke every relative
      # redirect from a server not on 80/443. Resolving against the URL that issued the
      # redirect rather than against the first one also keeps a chain that crosses hosts
      # pointing at the right place.
      redirect_location = get_redirect_location(api_response, Addressable::URI.parse(url).site)
      break if redirect_location.nil?

      url = redirect_location
      api_response = fetch(url)
    end

    api_response
  end
end
