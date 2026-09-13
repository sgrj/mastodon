# frozen_string_literal: true

# Publishes Activity Log events onto the Redis channel that ActivityLogSubscriber
# listens on (one subscriber per Puma worker, started in config/puma.rb).
class ActivityLogPublisher
  include Redisable

  CHANNEL = 'activity_log'

  # Uses the shared connection pool: this runs once per federated inbox request and
  # once per outbound delivery, so opening a dedicated connection each time would
  # exhaust Redis.
  #
  # `to_json` is what the fork's `Oj.dump` resolved to anyway -- config/initializers/oj.rb
  # set `mode: :compat, use_to_json: true`, so Oj handed the object straight to
  # ActiveSupport's Object#as_json (instance_values). The gem is gone from 4.7.1; the
  # wire format is unchanged.
  def publish(log_event)
    with_redis { |redis| redis.publish(CHANNEL, log_event.to_json) }
  end
end
