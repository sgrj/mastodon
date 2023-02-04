# frozen_string_literal: true
require 'redis'

class ActivityLogSubscriber
  def start
    redis = RedisConfiguration.new.connection

    redis.subscribe('activity_log') do |on|
      on.message do |channel, message|
        event = ActivityLogEvent.from_json_string(message)

        ActivityLogAudienceHelper.audience(event)
          .each { |username| ActivityLogger.log(username, event) }
      end
    end
  end
end
