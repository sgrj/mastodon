# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityLogger do
  after { described_class.reset }

  describe '.log' do
    it 'sends events to all listeners of the same id' do
      sse1 = instance_spy(ActionController::Live::SSE)
      sse2 = instance_spy(ActionController::Live::SSE)
      event = ActivityLogEvent.new('inbound', nil, nil, nil)

      described_class.register('test_id', sse1)
      described_class.register('test_id', sse2)

      described_class.log('test_id', event)

      expect(sse1).to have_received(:write).with(event)
      expect(sse2).to have_received(:write).with(event)
    end

    it 'sends events to all listeners even if some fail' do
      sse1 = instance_spy(ActionController::Live::SSE)
      sse2 = instance_spy(ActionController::Live::SSE)
      event = ActivityLogEvent.new('inbound', nil, nil, nil)

      allow(sse1).to receive(:write).and_raise('closed')

      described_class.register('test_id', sse1)
      described_class.register('test_id', sse2)

      described_class.log('test_id', event)

      expect(sse2).to have_received(:write).with(event)
    end

    it 'drops a listener whose write failed' do
      sse = instance_spy(ActionController::Live::SSE)
      event = ActivityLogEvent.new('inbound', nil, nil, nil)

      allow(sse).to receive(:write).and_raise('closed')

      described_class.register('test_id', sse)
      described_class.log('test_id', event)
      described_class.log('test_id', event)

      expect(sse).to have_received(:write).once
      expect(sse).to have_received(:close)
    end

    it 'does not send events to listeners of a different id' do
      sse = instance_spy(ActionController::Live::SSE)
      event = ActivityLogEvent.new('inbound', nil, nil, nil)

      described_class.register('test_id', sse)

      described_class.log('other_id', event)

      expect(sse).to_not have_received(:write).with(event)
    end

    it 'does not send events to listeners after unregistering' do
      sse1 = instance_spy(ActionController::Live::SSE)
      sse2 = instance_spy(ActionController::Live::SSE)
      event = ActivityLogEvent.new('inbound', nil, nil, nil)

      described_class.register('test_id', sse1)
      described_class.register('test_id', sse2)
      described_class.unregister('test_id', sse1)

      described_class.log('test_id', event)

      expect(sse1).to_not have_received(:write).with(event)
      expect(sse2).to have_received(:write).with(event)
    end

    it 'does nothing for an id nobody is listening to' do
      expect { described_class.log('nobody', ActivityLogEvent.new('inbound', nil, nil, nil)) }.to_not raise_error
    end
  end

  # The registry is process-wide and touched by Puma's request threads, the
  # ActivityLogSubscriber thread and the keep-alive thread at once. The fork's plain
  # Hash could lose a registration when two students connected simultaneously, and the
  # keep-alive walk could raise "can't add a new key into hash during iteration" inside
  # whichever request happened to be registering at the time. See PORTING.md.
  describe 'concurrent access' do
    it 'keeps every registration when many threads register at once' do
      listeners = Array.new(50) { instance_spy(ActionController::Live::SSE) }

      listeners.each_slice(5).map do |slice|
        Thread.new { slice.each { |sse| described_class.register('test_id', sse) } }
      end.each(&:join)

      described_class.log('test_id', ActivityLogEvent.new('inbound', nil, nil, nil))

      expect(listeners).to all(have_received(:write))
    end

    it 'does not raise while listeners are registered during a keep-alive broadcast' do
      # Deliberately not an rspec double: rspec-mocks' registry is not itself safe to
      # use from a thread other than the example's.
      sink = Class.new do
        def write(_event); end

        def close; end
      end

      described_class.register('existing', sink.new)

      registering = Thread.new do
        200.times { |i| described_class.register("student-#{i}", sink.new) }
      end

      expect { 200.times { described_class.send(:broadcast_keep_alive) } }.to_not raise_error
      expect { registering.join }.to_not raise_error
    end
  end
end
