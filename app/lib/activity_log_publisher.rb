class ActivityLogPublisher

  def initialize
    @redis = Redis.new
  end

  def publish(log_event)
    @redis.publish('activity_log', Oj.dump(log_event))
  end
end
