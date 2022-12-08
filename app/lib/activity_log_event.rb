# frozen_string_literal: true

class ActivityLogEvent

  def initialize
    @timestamp = Time.now.utc.iso8601
  end

  attr_accessor :type, :path, :data, :timestamp
end
