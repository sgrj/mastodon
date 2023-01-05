require 'json'
require 'rails_helper'

def activity_log_event_fixture(name)
  json_string = File.read(Rails.root.join('spec', 'fixtures', 'activity_log_events', name))

  ActivityLogEvent.from_json_string(json_string)
end

RSpec.describe ActivityLogAudienceHelper do
  describe '#audience' do
    around do |example|
      before = Rails.configuration.x.web_domain
      example.run
      Rails.configuration.x.web_domain = before
    end

    describe 'for inbound events' do
      it 'returns the author if the domain matches' do
        Rails.configuration.x.web_domain = 'example.com'
        outbound_event = activity_log_event_fixture('outbound.json')

        expect(ActivityLogAudienceHelper.audience(outbound_event)).to eq ['alice']
      end

      it 'returns nothing if the domain does not match' do
        Rails.configuration.x.web_domain = 'does-not-match.com'
        outbound_event = activity_log_event_fixture('outbound.json')

        expect(ActivityLogAudienceHelper.audience(outbound_event)).to eq []
      end

      it 'returns nothing if the activity does not have an actor' do
        Rails.configuration.x.web_domain = 'example.com'
        outbound_event = activity_log_event_fixture('outbound.json')
        outbound_event.data.delete('actor')

        expect(ActivityLogAudienceHelper.audience(outbound_event)).to eq []
      end
    end

    describe 'for outbound events' do
      it 'returns the inbox owner if it is sent to a personal inbox' do
        Rails.configuration.x.web_domain = 'example.com'
        inbound_event = activity_log_event_fixture('inbound-to-users-inbox.json')

        expect(ActivityLogAudienceHelper.audience(inbound_event)).to eq ['bob']
      end

      it 'returns direct audience from to, bto, cc, bcc if sent to public inbox' do
        Rails.configuration.x.web_domain = 'example.com'
        inbound_event = activity_log_event_fixture('inbound-with-multiple-recipients.json')

        expect(ActivityLogAudienceHelper.audience(inbound_event)).to match_array([
          'first-to',
          'second-to',
          'single-bto',
          'one-cc',
          'one-bcc'
        ])
      end
    end
  end
end
