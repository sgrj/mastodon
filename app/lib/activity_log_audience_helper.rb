# frozen_string_literal: true

class ActivityLogAudienceHelper

  def self.audience(activity_log_event)
    if activity_log_event.type == 'outbound'
      actor = activity_log_event.data['actor']

      if actor and match = actor.match(Regexp.new("https://#{Rails.configuration.x.local_domain}/users/(.*)"))
        return [match.captures[0]]
      else
        return []
      end
    end

    if activity_log_event.type == 'inbound'
      if match = activity_log_event.path.match(Regexp.new("https://#{Rails.configuration.x.local_domain}/users/(.*)/inbox"))
        return [match.captures[0]]
      end

      return []
    end

    return ['admin']
  end
end
