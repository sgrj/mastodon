# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityLogEvent do
  let(:data) { { 'type' => 'Follow', 'actor' => 'https://remote.example/users/alice' } }

  describe '#initialize' do
    it 'defaults the timestamp to now in ISO8601 UTC' do
      travel_to Time.utc(2024, 7, 21, 18, 18, 49) do
        expect(described_class.new('inbound', 'sender', 'path', data).timestamp).to eq '2024-07-21T18:18:49Z'
      end
    end

    it 'defaults failure to nil' do
      expect(described_class.new('inbound', 'sender', 'path', data).as_json['failure']).to be_nil
    end
  end

  # The serialized shape is a wire format. v4.1's config/initializers/oj.rb set
  # mode: :compat with use_to_json, so Oj.dump fell through to ActiveSupport's
  # Object#as_json (instance_values); `oj` is gone from 4.7.1 and `to_json` reaches the
  # same place directly. The Activity Log frontend JSON.parses this verbatim, so
  # changes here are breaking changes.
  describe 'serialization' do
    subject { JSON.parse(event.to_json) }

    let(:event) { described_class.new('outbound', 'https://academy.example/users/bob', 'https://remote.example/inbox', data, 'boom') }

    it 'round-trips every field the frontend reads' do
      expect(subject).to include(
        'type' => 'outbound',
        'sender' => 'https://academy.example/users/bob',
        'path' => 'https://remote.example/inbox',
        'data' => data,
        'failure' => 'boom'
      )
      expect(subject['timestamp']).to be_present
    end
  end

  describe '.from_json_string' do
    let(:event) { described_class.new('inbound', 'sender', 'path', data, 'failed') }

    it 'restores the event published on the Redis channel' do
      restored = described_class.from_json_string(event.to_json)

      expect(restored).to have_attributes(type: 'inbound', sender: 'sender', path: 'path', data: data)
      expect(restored.as_json['failure']).to eq 'failed'
    end

    # Oj.load(mode: :strict) raised Oj::ParseError here; JSON.parse raises
    # JSON::ParserError in the same place, which the subscriber's rescue catches.
    it 'raises on malformed JSON so the subscriber can log and carry on' do
      expect { described_class.from_json_string('not json') }.to raise_error(JSON::ParserError)
    end
  end
end
