# frozen_string_literal: true
require 'redis'

class ActivityLogSubscriber
  def start
    redis = RedisConfiguration.new.connection

    redis.subscribe('activity_log') do |on|
      on.message do |channel, message|
        begin
          event = ActivityLogEvent.from_json_string(message)

          ActivityLogAudienceHelper.audience(event)
            .each { |username| ActivityLogger.log(username, event) }
        rescue => e
          Rails.logger.error (["Error parsing #{message}. #{e.class}: #{e.message}"]+e.backtrace).join("\n")
        end
      end
    end
  end
end
