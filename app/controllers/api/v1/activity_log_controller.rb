# frozen_string_literal: true

class Api::V1::ActivityLogController < Api::BaseController
  include ActionController::Live

  # before_action -> { doorkeeper_authorize! :read }, only: [:show]
  before_action :require_user!

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  def index
    render :text => "hello world"
  end

  def show
    response.headers['Content-Type'] = 'text/event-stream'
    # hack to avoid computing Etag, which delays sending of data
    response.headers['Last-Modified'] = Time.now.httpdate

    sse = SSE.new(response.stream)

    # id = current_account.local_username_and_domain
    id = current_account.username

    begin
      ActivityLogger.register(id, sse)

      while true
        event = ActivityLogEvent.new
        event.type = "keep-alive"
        ActivityLogger.log(id, event)
        sleep 10
      end
    ensure
      ActivityLogger.unregister(id)
      Rails.logger.error "closed log"
      sse.close
    end
  end
end
