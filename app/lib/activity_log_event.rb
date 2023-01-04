# frozen_string_literal: true

class ActivityLogEvent
  attr_accessor :type, :path, :data, :timestamp

  def self.from_json_string(json_string)
    json = Oj.load(json_string, mode: :strict)
    ActivityLogEvent.new(json['type'], json['path'], json['data'])
  end


  def initialize(type, path, data, timestamp = Time.now.utc.iso8601)
    @type = type
    @path = path
    @data = data
    @timestamp
  end
end
