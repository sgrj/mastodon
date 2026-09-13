# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduler::OldAccountCleanupScheduler do
  subject { described_class.new }

  # The underscore heuristic is the whole safety net, so every example carries a control
  # account on each side of it. Cluster 4 builds an academy username as
  # `"First Last".parameterize(separator: '_')`, so a generated account always has an
  # underscore; `alice`, and the maintainer's own account, never do. The fork learned this
  # the hard way -- see its commits "do not delete crepels account" and "do not delete
  # alice account".
  let!(:generated_account) { Fabricate(:account, username: 'octavia_mildmoon', created_at: 25.hours.ago) }
  let!(:alice) { Fabricate(:account, username: 'alice', created_at: 25.hours.ago) }

  describe '#perform' do
    context 'when the pull queue is backed up past MAX_PULL_SIZE' do
      before do
        allow(Sidekiq::Queue).to receive(:new).and_call_original
        allow(Sidekiq::Queue)
          .to receive(:new)
          .with('pull')
          .and_return(instance_double(Sidekiq::Queue, size: described_class::MAX_PULL_SIZE + 1))
      end

      it 'marks nothing and enqueues nothing' do
        expect { subject.perform }
          .to_not change { generated_account.reload.requested_deletion_at }.from(nil)
        expect(AccountDeletionWorker).to_not have_enqueued_sidekiq_job
      end
    end

    # Everything below reads the real queue depth. `Sidekiq::Testing` replaces the client,
    # not the API, so `Sidekiq::Queue#size` is still an `LLEN queue:pull` against the test
    # Redis -- which is empty, and which keeps this an exercise of the Sidekiq 8 API rather
    # than of a stub.
    it 'marks the generated account deleted and hands it to AccountDeletionWorker' do
      subject.perform

      expect(generated_account.reload.requested_deletion_at).to_not be_nil
      expect(AccountDeletionWorker)
        .to have_enqueued_sidekiq_job(generated_account.id, { 'reserve_username' => false })
    end

    it 'leaves an account without an underscore alone' do
      subject.perform

      expect(alice.reload.requested_deletion_at).to be_nil
      expect(AccountDeletionWorker)
        .to_not have_enqueued_sidekiq_job(alice.id, { 'reserve_username' => false })
    end

    # A marked account leaves the `without_suspended` scope, so a second run skips it. It
    # has to: `Account#mark_deleted!` calls `create_deletion_request!`, and a `has_one`
    # given a second row leaves the account with two.
    it 'does not hand over an account it has already handed over' do
      subject.perform

      expect { subject.perform }
        .to_not change(AccountDeletionRequest, :count)
    end

    it 'hands over at most MAX_DELETIONS_PER_JOB accounts per run' do
      described_class::MAX_DELETIONS_PER_JOB.times { |i| Fabricate(:account, username: "student_#{i}", created_at: 25.hours.ago) }

      expect { subject.perform }
        .to change(AccountDeletionRequest, :count).by(described_class::MAX_DELETIONS_PER_JOB)
    end

    describe 'the accounts that actually disappear', :inline_jobs do
      let!(:young_account) { Fabricate(:account, username: 'young_account', created_at: 23.hours.ago) }
      let!(:remote_account) { Fabricate(:account, username: 'remote_account', domain: 'example.com', created_at: 25.hours.ago) }
      # `Account#deleted?` and `#suspended?` are both false for the instance actor, so
      # `AccountDeletionWorker` would refuse it anyway -- but give it a username the cleanup
      # would otherwise match, so `without_instance_actor` is the thing under test rather
      # than a lucky second line of defence.
      let!(:instance_actor) { Account.representative.tap { |account| account.update!(username: 'instance_actor', created_at: 25.hours.ago) } }

      it 'removes auto-generated accounts older than one day' do
        expect { subject.perform }
          .to change { Account.exists?(generated_account.id) }.from(true).to(false)
      end

      it 'does not remove auto-generated accounts younger than one day' do
        expect { subject.perform }
          .to_not change { Account.exists?(young_account.id) }.from(true)
      end

      it 'does not remove accounts without an underscore' do
        expect { subject.perform }
          .to_not change { Account.exists?(alice.id) }.from(true)
      end

      it 'does not remove accounts with an underscore from other instances' do
        expect { subject.perform }
          .to_not change { Account.exists?(remote_account.id) }.from(true)
      end

      it 'does not remove the instance actor' do
        expect { subject.perform }
          .to_not change { Account.exists?(instance_actor.id) }.from(true)
      end

      # `web_finger_overrides.account_id` is `on_delete: :cascade` (Cluster 2) precisely for
      # this: a student uses the WebFinger Forge, and a day later the cleanup deletes them.
      # Without the cascade the deletion dies on a dangling reference.
      it 'removes a generated account that used the WebFinger Forge, along with its override' do
        override = Fabricate(:web_finger_override, account: generated_account)

        expect { subject.perform }
          .to change { Account.exists?(generated_account.id) }.from(true).to(false)
          .and change { WebFingerOverride.exists?(override.id) }.from(true).to(false)
      end
    end
  end
end
