# frozen_string_literal: true

class ActivityLogAudienceHelper

  def self.audience(activity_log_event)
    domain = Rails.configuration.x.local_domain

    if activity_log_event.type == 'outbound'
      actor = activity_log_event.data['actor']

      if actor and match = actor.match(Regexp.new("https://#{domain}/users/(.*)"))
        return [match.captures[0]]
      else
        return []
      end
    end

    if activity_log_event.type == 'inbound'
      if match = activity_log_event.path.match(Regexp.new("https://#{domain}/users/(.*)/inbox"))
        return [match.captures[0]]
      elsif activity_log_event.path == "https://#{domain}/inbox"

      end

      return []
    end

    return []
  end
end
