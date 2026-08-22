# frozen_string_literal: true

class ActivityLogAudienceHelper

  def self.audience(activity_log_event)
    domain = Rails.configuration.x.web_domain

    if activity_log_event.type == 'outbound'
      sender = activity_log_event.sender

      if sender and match = sender.match(Regexp.new("https://#{domain}/users/([^/]*)"))
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
          .concat(owner(activity_log_event.data))
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
      if match = string_or_array.match(Regexp.new("https://#{domain}/users/([^/]*)"))
        [match.captures[0]]
      elsif string_or_array.ends_with?("/followers")
        # The URI comes from a remote server over the federated inbox, so it must be
        # bound as a parameter rather than interpolated. Only local accounts are
        # returned: these usernames are ActivityLogger routing keys, and a remote
        # follower would otherwise be routed at whichever local user shares its name.
        Account
          .joins('JOIN follows ON follows.account_id = accounts.id')
          .joins('JOIN accounts AS followed ON follows.target_account_id = followed.id')
          .where('followed.followers_url = ?', string_or_array)
          .where(accounts: { domain: nil })
          .pluck(:username)
      else
        []
      end
    else
      string_or_array.flat_map { |inner| self.actors(inner) }
    end
  end

  def self.owner(string_or_object)
    domain = Rails.configuration.x.web_domain

    if string_or_object.nil?
      []
    elsif string_or_object.is_a?(String)
      if match = string_or_object.match(Regexp.new("https://#{domain}/users/([^/]*)"))
        [match.captures[0]]
      else
        []
      end
    else
      self.owner(string_or_object['object'])
    end
  end
end
