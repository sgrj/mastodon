require 'json'
require 'rails_helper'

def activity_log_event_fixture(name)
  json_string = File.read(Rails.root.join('spec', 'fixtures', 'activity_log_events', name))

  ActivityLogEvent.from_json_string(json_string)
end

RSpec.describe ActivityLogger do

  after(:each) do
    ActivityLogger.reset
  end

  describe 'log' do

    it 'sends events to all listeners of the same id' do
      sse1 = spy('sse1')
      sse2 = spy('sse2')
      event = double('event')

      ActivityLogger.register('test_id', sse1)
      ActivityLogger.register('test_id', sse2)

      ActivityLogger.log('test_id', event)

      expect(sse1).to have_received(:write).with(event)
      expect(sse2).to have_received(:write).with(event)
    end

    it 'sends events to all listeners even if some fail' do
      sse1 = spy('sse1')
      sse2 = spy('sse2')
      event = double('event')

      allow(sse1).to receive(:write).and_throw(:error)

      ActivityLogger.register('test_id', sse1)
      ActivityLogger.register('test_id', sse2)

      ActivityLogger.log('test_id', event)

      expect(sse2).to have_received(:write).with(event)
    end

    it 'does not send events to listeners of a different id' do
      sse = spy('sse')
      event = double('event')

      ActivityLogger.register('test_id', sse)

      ActivityLogger.log('other_id', event)

      expect(sse).to_not have_received(:write).with(event)
    end

    it 'does not send events to listeners after unregistering' do
      sse1 = spy('sse1')
      sse2 = spy('sse2')
      event = double('event')

      ActivityLogger.register('test_id', sse1)
      ActivityLogger.register('test_id', sse2)
      ActivityLogger.unregister('test_id', sse1)

      ActivityLogger.log('test_id', event)

      expect(sse1).to_not have_received(:write).with(event)
      expect(sse2).to have_received(:write).with(event)
    end
  end
end
