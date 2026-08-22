# frozen_string_literal: true

require 'rails_helper'
require 'activity_log_subscriber'

# End-to-end test of the Activity Log, the fork's headline feature.
#
# The real path is: inbox controller / delivery worker
#   -> ActivityLogPublisher (Redis PUBLISH)
#   -> ActivityLogSubscriber (Redis SUBSCRIBE, one per Puma worker)
#   -> ActivityLogAudienceHelper (which local users should see this?)
#   -> ActivityLogger (per-username SSE registry)
#   -> the student's browser.
#
# Everything but the browser runs here, against a real Redis. If an upstream merge
# breaks the wiring, this is the spec that should catch it.
#
# Audience resolution is kept to the regex-only branches on purpose: the subscriber
# runs on its own thread and therefore its own database connection, which cannot see
# rows this example has not committed. The database-backed followers expansion is
# covered in spec/lib/activity_log_audience_helper_spec.rb instead.
RSpec.describe 'Activity Log pipeline' do
  subject(:publisher) { ActivityLogPublisher.new }

  let(:domain)   { Rails.configuration.x.web_domain }
  let(:listener) { FakeSse.new }

  # Minimal stand-in for ActionController::Live::SSE.
  class FakeSse
    def initialize
      @events = Queue.new
    end

    def write(event)
      @events << event
    end

    def close; end

    # Waits for the pipeline to deliver, rather than sleeping a fixed amount.
    def next_event(timeout: 5)
      Timeout.timeout(timeout) { @events.pop }
    rescue Timeout::Error
      nil
    end

    def empty?
      @events.empty?
    end
  end

  around do |example|
    thread = Thread.new { ActivityLogSubscriber.new.start }
    begin
      wait_for_pipeline
      example.run
    ensure
      thread.kill
      thread.join(5)
    end
  end

  # Redis SUBSCRIBE takes a moment to register, and anything published before then is
  # simply dropped. Rather than inspect the server (the channel is namespaced per
  # TEST_ENV_NUMBER, see lib/mastodon/redis_config.rb), push probe events through the
  # real pipeline until one comes out the far end.
  def wait_for_pipeline(timeout: 15)
    probe = FakeSse.new
    ActivityLogger.register('pipeline_probe', probe)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      publisher.publish(
        ActivityLogEvent.new('inbound', 'https://probe.example/users/probe', "https://#{domain}/users/pipeline_probe/inbox", { 'type' => 'Probe' })
      )
      break if probe.next_event(timeout: 0.25)
      raise 'the Activity Log pipeline never came up' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
  ensure
    ActivityLogger.unregister('pipeline_probe', probe)
  end

  def event_fixture(name)
    Oj.load(File.read(Rails.root.join('spec', 'fixtures', 'activity_log_events', "#{name}.json")), mode: :strict)
  end

  describe 'an inbound activity addressed to a personal inbox' do
    let(:event) do
      ActivityLogEvent.new(
        'inbound',
        'https://remote.example/users/alice',
        "https://#{domain}/users/bob/inbox",
        { 'type' => 'Follow', 'actor' => 'https://remote.example/users/alice' }
      )
    end

    it 'reaches the addressed user' do
      ActivityLogger.register('bob', listener)

      publisher.publish(event)

      delivered = listener.next_event
      expect(delivered).to_not be_nil, 'the activity never reached the listener'
      expect(delivered.type).to eq 'inbound'
      expect(delivered.path).to eq "https://#{domain}/users/bob/inbox"
      expect(delivered.data['type']).to eq 'Follow'
    end

    it 'does not reach anybody else' do
      ActivityLogger.register('carol', listener)

      publisher.publish(event)

      expect(listener.next_event(timeout: 1)).to be_nil
    end
  end

  describe 'an inbound activity to the shared inbox' do
    let(:event) do
      ActivityLogEvent.new(
        'inbound',
        'https://remote.example/users/alice',
        "https://#{domain}/inbox",
        {
          'type' => 'Create',
          'to' => ["https://#{domain}/users/bob"],
          'cc' => ["https://#{domain}/users/carol"],
        }
      )
    end

    it 'fans out to every addressed local user' do
      bob   = FakeSse.new
      carol = FakeSse.new
      dave  = FakeSse.new

      ActivityLogger.register('bob', bob)
      ActivityLogger.register('carol', carol)
      ActivityLogger.register('dave', dave)

      publisher.publish(event)

      expect(bob.next_event).to_not be_nil
      expect(carol.next_event).to_not be_nil
      expect(dave.next_event(timeout: 1)).to be_nil
    end
  end

  describe 'an outbound activity' do
    let(:event) do
      ActivityLogEvent.new(
        'outbound',
        "https://#{domain}/users/bob",
        'https://remote.example/users/alice/inbox',
        { 'type' => 'Follow' },
        'remote.example responded with status 500'
      )
    end

    it 'is routed back to the sending user, carrying the failure' do
      ActivityLogger.register('bob', listener)

      publisher.publish(event)

      delivered = listener.next_event
      expect(delivered).to_not be_nil
      expect(delivered.type).to eq 'outbound'
      expect(delivered.as_json['failure']).to eq 'remote.example responded with status 500'
    end
  end

  describe 'delivering to several listeners for one user' do
    it 'reaches every open browser tab' do
      first  = FakeSse.new
      second = FakeSse.new

      ActivityLogger.register('bob', first)
      ActivityLogger.register('bob', second)

      publisher.publish(
        ActivityLogEvent.new('inbound', 'https://remote.example/users/alice', "https://#{domain}/users/bob/inbox", { 'type' => 'Like' })
      )

      expect(first.next_event).to_not be_nil
      expect(second.next_event).to_not be_nil
    end
  end

  describe 'a malformed message on the channel' do
    it 'is logged and does not kill the subscriber' do
      ActivityLogger.register('bob', listener)

      redis.publish('activity_log', 'not json at all')
      publisher.publish(
        ActivityLogEvent.new('inbound', 'https://remote.example/users/alice', "https://#{domain}/users/bob/inbox", { 'type' => 'Like' })
      )

      expect(listener.next_event).to_not be_nil
    end
  end
end
