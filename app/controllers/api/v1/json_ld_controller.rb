# frozen_string_literal: true

require "net/http"
require "uri"


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
        uri = URI.parse(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 3
        http.read_timeout = 5
        http.write_timeout = 5
        api_response = http.request(Net::HTTP::Get.new(uri.request_uri))

        io.write("HTTP/1.1 #{api_response.status}\r\n")
        io.write("Content-Type: #{api_response.headers['Content-Type']}\r\n")
        io.write("Connection: close\r\n")
        io.write("\r\n")
        io.write(api_response.body)
      ensure
        io.close
      end
    }
  end
end
