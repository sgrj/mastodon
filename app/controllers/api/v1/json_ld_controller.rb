# frozen_string_literal: true

require 'faraday'

class Api::V1::JsonLdController < Api::BaseController
  include ActionController::Live

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  def show
    url = params[:url]

    api_response = Faraday.get(url, nil, {'Accept' => 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"'})

    response.headers['Content-Type'] = api_response.headers['Content-Type']

    render body: api_response.body, status: api_response.status
  end
end
