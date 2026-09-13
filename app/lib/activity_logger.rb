# frozen_string_literal: true

# Process-wide registry of the Activity Log SSE streams this Puma worker is holding
# open, keyed by local username.
#
# Three kinds of thread touch it: Puma's request threads register and unregister one
# entry per open browser tab, the ActivityLogSubscriber thread fans inbound and outbound
# activities out over it, and the keep-alive thread walks every key. A bare Hash is not
# safe under that, so the registry itself is guarded -- but the writes to the sockets
# deliberately happen outside the lock, because an SSE write can block on a slow client
# and must not stall every other student's log.
class ActivityLogger
  KEEP_ALIVE_INTERVAL = 10.seconds

  @loggers = {}
  @mutex   = Mutex.new

  class << self
    def register(id, sse)
      @mutex.synchronize { (@loggers[id] ||= []) << sse }
    end

    def unregister(id, sse)
      @mutex.synchronize do
        registered = @loggers[id]
        next if registered.nil?

        registered.delete(sse)
        @loggers.delete(id) if registered.empty?
      end
    end

    def log(id, event)
      # Iterate over a snapshot: a failing write unregisters the logger, and mutating
      # the array being iterated would silently skip the following logger.
      listeners(id).each do |logger|
        logger.write event
      rescue
        Rails.logger.debug { "activity log: dropping closed listener for #{id}" }
        # Closing an already-broken socket can raise in its own right, and this runs on
        # the subscriber thread: letting it escape would skip every listener after this
        # one in the snapshot.
        begin
          logger.close
        rescue
          nil
        end
        unregister(id, logger)
      end
    end

    def reset
      @mutex.synchronize { @loggers.clear }
    end

    # Started once per Puma worker from config/puma.rb. Without it an idle Activity Log
    # connection is closed by whatever proxy sits in front of us.
    def start_keep_alive_thread
      Thread.new do
        Thread.current.name = 'activity-log-keep-alive'

        loop do
          begin
            broadcast_keep_alive
          rescue => e
            Rails.logger.error { "activity log: keep-alive failed: #{e.class}: #{e.message}" }
          end

          sleep KEEP_ALIVE_INTERVAL
        end
      end
    end

    private

    def listeners(id)
      @mutex.synchronize { @loggers[id]&.dup } || []
    end

    def broadcast_keep_alive
      event = ActivityLogEvent.new('keep-alive', nil, nil, nil)

      # Snapshot the keys under the lock rather than iterating the Hash itself: a
      # request thread registering a new listener mid-iteration would raise
      # "can't add a new key into hash during iteration" in the middle of its own
      # request, turning somebody opening the Activity Log into a 500.
      keys = @mutex.synchronize { @loggers.keys }
      keys.each { |key| log(key, event) }
    end
  end
end
