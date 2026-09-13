# frozen_string_literal: true

require 'redis'

# One per Puma worker, started from config/puma.rb. Listens on the Redis channel
# ActivityLogPublisher writes to and fans each event out to the local users whose
# Activity Log should show it.
#
# This file is not autoloadable -- `lib` is on $LOAD_PATH but not on Rails' autoload
# path -- so config/puma.rb requires it explicitly, and so does the pipeline spec.
class ActivityLogSubscriber
  def start
    redis = RedisConnection.new.connection

    redis.subscribe(ActivityLogPublisher::CHANNEL) do |on|
      on.message { |_channel, message| handle(message) }
    end
  end

  private

  # Wrapped in the Rails executor because this runs on a thread the process spawned by
  # hand: ActivityLogAudienceHelper's followers branch issues a real query, and without
  # the executor the connection it leases is never returned to the pool. It also makes
  # autoloading from this thread safe, which a bare Thread.new is not.
  def handle(message)
    Rails.application.executor.wrap do
      event = ActivityLogEvent.from_json_string(message)

      ActivityLogAudienceHelper.audience(event).each do |username|
        ActivityLogger.log(username, event)
      end
    end
  rescue => e
    Rails.logger.error { (["Error parsing #{message}. #{e.class}: #{e.message}"] + Array(e.backtrace)).join("\n") }
  end
end
