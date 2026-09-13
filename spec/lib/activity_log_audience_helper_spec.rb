# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityLogAudienceHelper do
  def activity_log_event_fixture(name)
    ActivityLogEvent.from_json_string(Rails.root.join('spec', 'fixtures', 'activity_log_events', name).read)
  end

  describe '.audience' do
    around do |example|
      before = Rails.configuration.x.web_domain
      Rails.configuration.x.web_domain = 'example.com'
      example.run
      Rails.configuration.x.web_domain = before
    end

    context 'with outbound events' do
      it 'returns the sender if the domain matches' do
        outbound_event = activity_log_event_fixture('outbound.json')

        expect(described_class.audience(outbound_event)).to eq ['alice']
      end

      it 'returns nothing if the domain does not match' do
        Rails.configuration.x.web_domain = 'does-not-match.com'
        outbound_event = activity_log_event_fixture('outbound.json')

        expect(described_class.audience(outbound_event)).to eq []
      end

      it 'returns nothing if the activity does not have a sender' do
        outbound_event_tmp = activity_log_event_fixture('outbound.json')
        outbound_event = ActivityLogEvent.new(
          outbound_event_tmp.type,
          nil,
          outbound_event_tmp.path,
          outbound_event_tmp.data
        )

        expect(described_class.audience(outbound_event)).to eq []
      end
    end

    context 'with inbound events' do
      it 'returns the inbox owner if it is sent to a personal inbox' do
        inbound_event = activity_log_event_fixture('inbound-to-users-inbox.json')

        expect(described_class.audience(inbound_event)).to eq ['bob']
      end

      it 'returns direct audience from to, bto, cc, bcc if sent to public inbox' do
        inbound_event = activity_log_event_fixture('inbound-with-multiple-recipients.json')

        expect(described_class.audience(inbound_event)).to contain_exactly('first-to', 'second-to', 'single-bto', 'one-cc', 'one-bcc')
      end

      it 'returns followers from to, bto, cc, bcc if sent to public inbox' do
        inbound_event = activity_log_event_fixture('inbound-with-follower-recipients.json')

        bob = Fabricate(:account, username: 'bob', domain: 'other.org', followers_url: 'https://other.org/users/bob/followers')
        Fabricate(:account, username: 'first_follower').follow!(bob)
        Fabricate(:account, username: 'second_follower').follow!(bob)

        expect(described_class.audience(inbound_event)).to contain_exactly('first_follower', 'second_follower')
      end

      it 'returns owner of an object if sent to public inbox' do
        inbound_event = activity_log_event_fixture('inbound-with-object-owner.json')

        expect(described_class.audience(inbound_event)).to contain_exactly('owner')
      end

      it 'returns owner of an object if sent to public inbox, even if object is nested' do
        inbound_event = activity_log_event_fixture('inbound-with-nested-object-owner.json')

        expect(described_class.audience(inbound_event)).to contain_exactly('owner')
      end

      it 'removes duplicates from audience' do
        inbound_event = activity_log_event_fixture('inbound-with-duplicate-recipients.json')

        expect(described_class.audience(inbound_event)).to contain_exactly('first-to', 'second-to')
      end

      it 'handles null in array correctly' do
        inbound_event = activity_log_event_fixture('inbound-with-null-in-array.json')

        expect(described_class.audience(inbound_event)).to be_empty
      end

      # ActivityPub::InboxesController now publishes upstream's memoized `parsed_body`,
      # which is nil for a body that is not JSON rather than raising the way the fork's
      # own Oj.load did. The event still reaches the subscriber, so audience resolution
      # has to survive it.
      it 'returns nothing when the activity could not be parsed' do
        event = ActivityLogEvent.new('inbound', 'https://other.org/users/eve', 'https://example.com/inbox', nil)

        expect(described_class.audience(event)).to eq []
      end
    end

    context 'when resolving a followers collection' do
      def audience_for(followers_uri)
        described_class.audience(
          ActivityLogEvent.new(
            'inbound', 'https://other.org/users/eve', 'https://example.com/inbox',
            { 'to' => [followers_uri] }
          )
        )
      end

      # The followers URI arrives from a remote server over the federated inbox, so it
      # is entirely attacker-controlled, and it reaches the query only when it ends in
      # "/followers" -- so a payload has to keep that suffix to get there at all.
      it 'does not let a followers URI comment out the rest of the query' do
        bob = Fabricate(:account, username: 'bob', domain: 'other.org', followers_url: 'https://other.org/users/bob/followers')
        Fabricate(:account, username: 'a_follower').follow!(bob)
        Fabricate(:account, username: 'an_unrelated_account')

        # Interpolated, this closes the string literal and comments out the closing
        # quote, leaving `WHERE followers_url = 'https://x' OR 1=1`, which matches
        # every row and returns every account on the instance.
        expect(audience_for("https://x' OR 1=1 -- /followers")).to eq []
      end

      it 'does not raise on a followers URI containing a bare quote' do
        Fabricate(:account, username: 'bystander')

        expect { audience_for("https://other.org/x'/followers") }.to_not raise_error
        expect(audience_for("https://other.org/x'/followers")).to eq []
      end

      # The returned usernames are used as ActivityLogger routing keys, and those keys
      # are local usernames. A remote follower would otherwise route another
      # instance's activities at whichever local user happens to share its username.
      it 'only returns local followers' do
        bob = Fabricate(:account, username: 'bob', domain: 'other.org', followers_url: 'https://other.org/users/bob/followers')
        Fabricate(:account, username: 'local_follower').follow!(bob)
        Fabricate(:account, username: 'remote_follower', domain: 'elsewhere.example').follow!(bob)

        expect(audience_for('https://other.org/users/bob/followers')).to eq ['local_follower']
      end
    end

    # The recipient URIs are written by whoever sent the activity. The fork's regexes
    # were unanchored, so a remote server could put the local actor URI anywhere inside
    # a URI of its own and have the activity show up in that student's log.
    context 'when a recipient URI only contains a local actor URI' do
      it 'does not treat it as a local recipient' do
        event = ActivityLogEvent.new(
          'inbound', 'https://other.org/users/eve', 'https://example.com/inbox',
          { 'to' => ['https://evil.example/https://example.com/users/bob'] }
        )

        expect(described_class.audience(event)).to eq []
      end
    end
  end
end
