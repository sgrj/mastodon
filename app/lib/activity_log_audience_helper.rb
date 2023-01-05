# frozen_string_literal: true

class ActivityLogAudienceHelper

  def self.audience(activity_log_event)
    domain = Rails.configuration.x.web_domain

    if activity_log_event.type == 'outbound'
      actor = activity_log_event.data['actor']

      if actor and match = actor.match(Regexp.new("https://#{domain}/users/([^/]*)"))
        [match.captures[0]]
      else
        []
      end
    elsif activity_log_event.type == 'inbound'
      if match = activity_log_event.path.match(Regexp.new("https://#{domain}/users/([^/]*)/inbox"))
        [match.captures[0]]
      elsif activity_log_event.path == "https://#{domain}/inbox"
        ['to', 'bto', 'cc', 'bcc']
          .map { |target| actors(activity_log_event.data[target]) }
          .flatten
          .uniq
      else
        []
      end
    else
      []
    end
  end

  private

  def self.actors(string_or_array)
    domain = Rails.configuration.x.web_domain

    if string_or_array.nil?
      []
    elsif string_or_array.is_a?(String)
      self.actors([string_or_array])
    else
      string_or_array.map do |string|
        if match = string.match(Regexp.new("https://#{domain}/users/([^/]*)"))
          match.captures[0]
        elsif string.ends_with?("/followers")
          Account
            .joins(
              "JOIN follows ON follows.account_id = accounts.id
                JOIN accounts AS followed ON follows.target_account_id = followed.id
                WHERE followed.followers_url = '#{string}'")
            .map { |account| account.username }
        else
          nil
        end
      end.flatten.compact
    end
  end
end
