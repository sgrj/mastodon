# frozen_string_literal: true

require "faraday"

class Api::V1::JsonLdController < Api::BaseController
  include ActionController::Live

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  def show
    url = params[:url]

    request.env['rack.hijack'].call
    io = request.env['rack.hijack_io']
    Thread.new {
      begin
        conn = Faraday::Connection.new
        conn.options.timeout = 5

        api_response = conn.get(url, nil, {'Accept' => 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"'})

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
