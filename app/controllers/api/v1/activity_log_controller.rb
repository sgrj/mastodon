# frozen_string_literal: true

# The browser holds one EventSource against this endpoint for the whole session. The
# Rack socket is hijacked and handed to ActivityLogger, keyed by the account's username
# -- which is the key ActivityLogAudienceHelper resolves an event's audience to.
class Api::V1::ActivityLogController < Api::BaseController
  include ActionController::Live

  before_action :require_user!

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  def show
    response.headers['Content-Type'] = 'text/event-stream'
    # Set so Rack does not compute an ETag, which would buffer the response and delay
    # the first event.
    response.headers['Last-Modified'] = Time.now.httpdate

    # adapted from https://blog.chumakoff.com/en/posts/rails_sse_rack_hijacking_api
    response.headers['rack.hijack'] = proc do |stream|
      ActivityLogger.register(current_account.username, SSE.new(stream))
    end

    head 200
  end
end
