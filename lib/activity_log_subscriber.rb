# frozen_string_literal: true
require 'redis'

class ActivityLogSubscriber
  def start
    redis = Redis.new

    redis.subscribe('activity_log') do |on|
      on.message do |channel, message|
        json = Oj.load(message, mode: :strict)
        event = ActivityLogEvent.new(json['type'], json['path'], json['data'])

        ActivityLogger.log('admin', event)
      end
    end
  end
end
