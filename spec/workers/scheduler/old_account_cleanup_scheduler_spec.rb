require 'json'
require 'rails_helper'

RSpec.describe Scheduler::OldAccountCleanupScheduler do
  subject { described_class.new }
  let!(:generated_user) { Fabricate(:account, username: 'containing_underscore', created_at: 25.hours.ago) }
  let!(:alice) { Fabricate(:account, username: 'alice', created_at: 25.hours.ago) }
  let!(:generated_user_other_instance) { Fabricate(:account, username: 'containing_underscore', domain: 'example.com', created_at: 25.hours.ago) }
  let!(:instance_actor) { Fabricate(:account, id: 99, created_at: 25.hours.ago) }

  describe '#perform' do
    it 'removes auto-generated user-accounts that are older than one day' do
      expect { subject.perform }.to change { Account.exists?(generated_user.id) }.from(true).to(false)
    end

    it 'does not remove auto-generated user-accounts that are younger than one day' do
      generated_user.update!(created_at: 23.hours.ago)
      expect { subject.perform }.not_to change { Account.exists?(generated_user.id) }.from(true)
    end

    it 'does not remove accounts with underscores from other instances' do
      expect { subject.perform }.not_to change { Account.exists?(generated_user_other_instance.id) }.from(true)
    end

    it 'does not remove accounts without underscores' do
      expect { subject.perform }.not_to change { Account.exists?(alice.id) }.from(true)
    end

    it 'does not remove instance actor' do
      expect { subject.perform }.not_to change { Account.exists?(instance_actor.id) }.from(true)
    end
  end
end
