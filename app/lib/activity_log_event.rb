# frozen_string_literal: true

# One entry in a student's Activity Log: an activity that arrived at a local inbox, or
# one this instance delivered to a remote one.
#
# Instances are serialized onto a Redis channel by ActivityLogPublisher and rebuilt on
# the far side by ActivityLogSubscriber, so the field names below are a wire format the
# frontend also reads. Changing them is a breaking change.
class ActivityLogEvent
  attr_accessor :type, :sender, :path, :data, :timestamp

  def self.from_json_string(json_string)
    json = JSON.parse(json_string)

    new(json['type'], json['sender'], json['path'], json['data'], json['failure'])
  end

  def initialize(type, sender, path, data, failure = nil, timestamp = Time.now.utc.iso8601)
    @type      = type
    @sender    = sender
    @path      = path
    @data      = data
    @timestamp = timestamp
    @failure   = failure
  end
end
