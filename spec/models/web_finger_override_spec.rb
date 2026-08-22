# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebFingerOverride, type: :model do
  describe 'associations' do
    it 'requires an account' do
      expect(described_class.new(value: '{}')).to_not be_valid
    end

    it 'is valid with an account' do
      expect(Fabricate.build(:web_finger_override)).to be_valid
    end
  end

  describe 'deleting the account' do
    let!(:account)  { Fabricate(:account) }
    let!(:override) { Fabricate(:web_finger_override, account: account) }

    # The foreign key gained ON DELETE CASCADE in
    # 20240721181849_add_cascade_delete_to_web_finger_overrides_account.rb, so that
    # Scheduler::OldAccountCleanupScheduler can delete day-old accounts without
    # tripping over a dangling override.
    it 'deletes the override along with the account' do
      expect { account.destroy! }.to change { described_class.exists?(override.id) }.from(true).to(false)
    end

    it 'does not block deletion via the database foreign key' do
      expect { Account.where(id: account.id).delete_all }.to_not raise_error
      expect(described_class.exists?(override.id)).to be false
    end
  end
end
