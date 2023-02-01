# frozen_string_literal: true

class Api::V1::ActivityLogController < Api::BaseController
  include ActionController::Live

  before_action :require_user!

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  def show
    response.headers['Content-Type'] = 'text/event-stream'
    # hack to avoid computing Etag, which delays sending of data
    response.headers['Last-Modified'] = Time.now.httpdate

    # adapted from https://blog.chumakoff.com/en/posts/rails_sse_rack_hijacking_api
    response.headers["rack.hijack"] = proc do |stream|
      ActivityLogger.register(current_account.username, SSE.new(stream))
    end

    head :ok
  end
end
