# frozen_string_literal: true

class ActivityLogger

  @@loggers = Hash.new

  def self.register(id, sse)
    Rails.logger.error "registering id #{id}"
    @@loggers[id] = sse
  end

  def self.unregister(id)
    Rails.logger.error "unregistering id #{id}"
    @@loggers.delete(id)
  end

  def self.log(id, event)
    Rails.logger.error "logging id #{id}, event #{event.type} #{event.data}, loggers #{@@loggers}"
    if @@loggers[id]
      Rails.logger.error "logged"
      @@loggers[id].write event
    end
  end
end
