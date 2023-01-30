# frozen_string_literal: true
require 'redis'

class ActivityLogSubscriber
  def start
    redis = RedisConfiguration.new.connection

    redis.subscribe('activity_log') do |on|
      on.message do |channel, message|
        json = Oj.load(message, mode: :strict)
        event = ActivityLogEvent.new(json['type'], json['path'], json['data'])

        ActivityLogAudienceHelper.audience(event)
          .each { |username| ActivityLogger.log(username, event) }
      end
    end
  end
end