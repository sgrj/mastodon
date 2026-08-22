# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityLogPublisher do
  subject(:publisher) { described_class.new }

  let(:event) do
    ActivityLogEvent.new('inbound', 'https://remote.example/users/alice', 'https://academy.example/inbox', { 'type' => 'Follow' })
  end

  describe '#publish' do
    it 'publishes the serialized event on the activity_log channel' do
      message = capture_one_message_on(described_class::CHANNEL) { publisher.publish(event) }

      expect(message).to_not be_nil, 'nothing arrived on the channel'
      expect(Oj.load(message, mode: :strict)).to include(
        'type' => 'inbound',
        'sender' => 'https://remote.example/users/alice',
        'path' => 'https://academy.example/inbox'
      )
    end

    # ActivityPub::InboxesController and ActivityPub::DeliveryWorker publish once per
    # inbound request and once per outbound delivery, so opening a dedicated connection
    # per publish would exhaust Redis on a busy instance.
    it 'uses the shared connection pool rather than opening a connection each time' do
      allow(RedisConfiguration).to receive(:with).and_call_original
      allow(RedisConfiguration).to receive(:new).and_call_original

      publisher.publish(event)

      expect(RedisConfiguration).to have_received(:with)
      expect(RedisConfiguration).to_not have_received(:new)
    end
  end

  # Subscribes on its own connection, waits until the subscription is live, runs the
  # block, and returns the first message that arrives.
  def capture_one_message_on(channel)
    messages = Queue.new
    ready    = Queue.new

    thread = Thread.new do
      RedisConfiguration.new.connection.subscribe(channel) do |on|
        on.subscribe { ready << true }
        on.message { |_ch, message| messages << message }
      end
    end

    Timeout.timeout(5) { ready.pop }
    yield

    Timeout.timeout(5) { messages.pop }
  rescue Timeout::Error
    nil
  ensure
    thread&.kill
    thread&.join(5)
  end
end
