# frozen_string_literal: true

class ActivityLogEvent
  attr_accessor :type, :sender, :path, :data, :timestamp

  def self.from_json_string(json_string)
    json = Oj.load(json_string, mode: :strict)
    ActivityLogEvent.new(json['type'], json['sender'], json['path'], json['data'], json['failure'])
  end


  def initialize(type, sender, path, data, failure = nil, timestamp = Time.now.utc.iso8601)
    @type = type
    @sender = sender
    @path = path
    @data = data
    @timestamp = timestamp
    @failure = failure
  end
end
