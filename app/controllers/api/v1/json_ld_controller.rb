# frozen_string_literal: true

require "faraday"
require "uri"

class Api::V1::JsonLdController < Api::BaseController
  include ActionController::Live

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  before_action :require_user!

  REQUEST_TARGET = '(request-target)'
  MAX_REDIRECTS = 5

  def show
    url = params[:url]

    request.env['rack.hijack'].call
    io = request.env['rack.hijack_io']
    Thread.new {
      begin
        api_response = follow_redirects(Faraday::Connection.new, url)

        io.write("HTTP/1.1 #{api_response.status}\r\n")
        io.write("Content-Type: #{api_response.headers['Content-Type']}\r\n")
        io.write("Access-Control-Allow-Origin: *\r\n")
        io.write("Connection: close\r\n")
        io.write("\r\n")
        io.write(api_response.body)
      rescue
        io.write("HTTP/1.1 500\r\n")
        io.write("Access-Control-Allow-Origin: *\r\n")
        io.write("Connection: close\r\n")
        io.write("\r\n")
      ensure
        io.close
      end
    }
  end

  private

  def signature(headers)
    account = Account.representative

    key_id = ActivityPub::TagManager.instance.key_uri_for(account)
    algorithm = 'rsa-sha256'
    signed_string = headers.map { |key, value| "#{key.downcase}: #{value}" }.join("\n")
    signature = Base64.strict_encode64(account.keypair.sign(OpenSSL::Digest.new('SHA256'), signed_string))

    "keyId=\"#{key_id}\",algorithm=\"#{algorithm}\",headers=\"#{headers.keys.join(' ').downcase}\",signature=\"#{signature}\""
  end

  def signed_headers(url_string)
    if url_string.include?(".well-known")
      return {'Accept': 'application/jrd+json'}
    end

    url = URI.parse(url_string)
    tmp_headers = {
      'Date': Time.now.utc.httpdate,
      'Host': url.host,
      'Accept': 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"',
    }
    tmp_headers[REQUEST_TARGET] = "get #{url_string.delete_prefix("#{url.scheme}://#{url.host}")}"
    additional_headers = {
      'Signature': signature(tmp_headers),
      'User-Agent': Mastodon::Version.user_agent,
    }
    tmp_headers.merge(additional_headers).except(REQUEST_TARGET)
  end

  def get_redirect_location(api_response, host)
    location = if [301, 302].include?(api_response.status)
                 api_response.headers['location']
               elsif api_response.status == 200
                 # for JSON-LD, the actual document might be at an alternate location specified by
                 # the link header; see https://www.w3.org/TR/json-ld11/#alternate-document-location
                 link_header = api_response.headers['link']
                 link_header&.match(/<([^>]+)>;\s*rel="alternate";\s*type="application\/ld\+json"/i)&.captures&.first
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
  def follow_redirects(conn, url)
    api_response = conn.get(url, nil, signed_headers(url))

    parsed_url = URI.parse(url)
    host = "#{parsed_url.scheme}://#{parsed_url.host}"

    MAX_REDIRECTS.times do
      redirect_location = get_redirect_location(api_response, host)
      break if redirect_location.nil?

      api_response = conn.get(redirect_location, nil, signed_headers(redirect_location))
    end

    api_response
  end
end
