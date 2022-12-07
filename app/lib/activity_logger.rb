# frozen_string_literal: true

class ActivityLogger

  @@loggers = Hash.new

  def self.register(id, sse)
    @@loggers[id] = sse
  end

  def self.unregister(id)
    @@loggers.delete(id)
  end

  def self.log(id, event)
    if @@loggers[id]
      @@loggers[id].write event
    end
  end
end
