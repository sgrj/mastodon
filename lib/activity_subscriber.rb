# frozen_string_literal: true
require 'redis'

class ActivitySubscriber
  def start
    redis = Redis.new

    redis.subscribe('activity_log') do |on|
      on.message do |channel, message|
        json = Oj.load(message, mode: :strict)
        event = ActivityLogEvent.new
        event.type = json['type']
        event.path = json['path']
        event.data = json['data']

        ActivityLogger.log('admin', event)
      end
    end
  end
end
