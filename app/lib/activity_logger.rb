# frozen_string_literal: true

class ActivityLogger

  @@loggers = Hash.new { |hash, key| hash[key] = [] }

  def self.register(id, sse)
    @@loggers[id] << sse
  end

  def self.unregister(id, sse)
    @@loggers[id].delete(sse)
  end

  def self.log(id, event)
    @@loggers[id].each do |logger|
      logger.write event
    rescue
      puts 'rescued'
      logger.close
      puts 'closed logger'
    end
  end

  def self.reset
    @@loggers.clear
  end

  Thread.new {
    while true
      event = ActivityLogEvent.new('keep-alive', nil, nil, nil)
      @@loggers.each_key do |key|
        ActivityLogger.log(key, event)
      end

      sleep 10
    end
  }
end
