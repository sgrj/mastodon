class ActivityLogPublisher

  def initialize
    @redis = RedisConfiguration.new.connection
  end

  def publish(log_event)
    @redis.publish('activity_log', Oj.dump(log_event))
  end
end
