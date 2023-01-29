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
end
