# frozen_string_literal: true

# Works out which local users should see an Activity Log event.
#
# The answers are local usernames, because that is the key ActivityLogger registers SSE
# streams under (see Api::V1::ActivityLogController). Everything here therefore matches
# actor URIs of the `https://<web domain>/users/<username>` shape -- which is why
# academy accounts are created with `id_scheme: :username_ap_id`; see PORTING.md.
class ActivityLogAudienceHelper
  AUDIENCE_FIELDS = %w(to bto cc bcc).freeze

  class << self
    def audience(activity_log_event)
      case activity_log_event.type
      when 'outbound'
        local_actor(activity_log_event.sender)
      when 'inbound'
        inbound_audience(activity_log_event)
      else
        []
      end
    end

    private

    def web_domain
      Rails.configuration.x.web_domain
    end

    # Anchored: the URIs in `to`/`cc` arrive from a remote server, and an unanchored
    # match would let `https://evil.example/https://academy.example/users/alice` show
    # up in alice's log.
    def local_actor_regex
      Regexp.new("\\Ahttps://#{Regexp.escape(web_domain)}/users/([^/]*)")
    end

    def personal_inbox_regex
      Regexp.new("\\Ahttps://#{Regexp.escape(web_domain)}/users/([^/]*)/inbox\\z")
    end

    def local_actor(uri)
      match = uri.is_a?(String) ? uri.match(local_actor_regex) : nil

      match ? [match[1]] : []
    end

    def inbound_audience(activity_log_event)
      path = activity_log_event.path
      match = path.is_a?(String) ? path.match(personal_inbox_regex) : nil

      return [match[1]] if match
      return [] unless path == "https://#{web_domain}/inbox"

      data = activity_log_event.data
      return [] unless data.is_a?(Hash)

      AUDIENCE_FIELDS
        .flat_map { |field| actors(data[field]) }
        .concat(owner(data))
        .uniq
    end

    def actors(string_or_array)
      case string_or_array
      when String
        actors_from_uri(string_or_array)
      when Array
        string_or_array.flat_map { |inner| actors(inner) }
      else
        []
      end
    end

    def actors_from_uri(uri)
      local = local_actor(uri)
      return local if local.any?
      return [] unless uri.ends_with?('/followers')

      local_followers_of(uri)
    end

    # The URI comes from a remote server over the federated inbox, so it must be
    # bound as a parameter rather than interpolated. Only local accounts are
    # returned: these usernames are ActivityLogger routing keys, and a remote
    # follower would otherwise be routed at whichever local user shares its name.
    def local_followers_of(followers_url)
      Account
        .joins('JOIN follows ON follows.account_id = accounts.id')
        .joins('JOIN accounts AS followed ON follows.target_account_id = followed.id')
        .where(followed: { followers_url: followers_url })
        .where(accounts: { domain: nil })
        .pluck(:username)
    end

    def owner(string_or_object)
      case string_or_object
      when String
        local_actor(string_or_object)
      when Hash
        owner(string_or_object['object'])
      else
        []
      end
    end
  end
end
