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

  def show
    url = params[:url]

    request.env['rack.hijack'].call
    io = request.env['rack.hijack_io']
    Thread.new {
      begin
        conn = Faraday::Connection.new

        api_response = conn.get(url, nil, signed_headers(url))

        max_redirects = 5
        while api_response.status == 301 || api_response.status == 302 and max_redirects > 0 do
          api_response = conn.get(api_response.headers['Location'], nil, signed_headers(api_response.headers['Location']))
          max_redirects -= 1
        end

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
end
