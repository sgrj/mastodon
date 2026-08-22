# frozen_string_literal: true

# Publishes Activity Log events onto the Redis channel that ActivityLogSubscriber
# listens on (one subscriber per Puma worker, started in config/puma.rb).
class ActivityLogPublisher
  include Redisable

  CHANNEL = 'activity_log'

  # Uses the shared connection pool: this runs once per federated inbox request and
  # once per outbound delivery, so opening a dedicated connection each time would
  # exhaust Redis.
  def publish(log_event)
    with_redis { |redis| redis.publish(CHANNEL, Oj.dump(log_event)) }
  end
end
