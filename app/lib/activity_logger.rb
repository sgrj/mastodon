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
      ActivityLogger.unregister(id, logger)
      puts 'closed logger'
    end
  end

  def self.reset
    @@loggers.clear
  end

  def self.start_keep_alive_thread
    Thread.new {
      while true
        event = ActivityLogEvent.new('keep-alive', nil, nil, nil)
        puts "writing keep-alive"
        @@loggers.each_key do |key|
          ActivityLogger.log(key, event)
        end

        sleep 10
      end
    }
  end
end
