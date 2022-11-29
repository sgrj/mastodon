# frozen_string_literal: true

class Api::V1::ActivityLogController < Api::BaseController
  include ActionController::Live

  # before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:index, :show]
  # before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:index, :show]

  # before_action :require_user!
  # before_action :set_list, except: [:index, :create]
  #
  #
  #
  class Foo
    attr_accessor :test
  end

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

    begin
      100.times {
        f = Foo.new
        f.test = "xxx"
        sse.write f.to_json
        sleep 1
      }
    ensure
      sse.close
    end
  end
end
