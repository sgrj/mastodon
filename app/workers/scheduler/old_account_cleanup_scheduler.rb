# frozen_string_literal: true

class Scheduler::OldAccountCleanupScheduler
  include Sidekiq::Worker

  # Each processed deletion request may enqueue an enormous
  # amount of jobs in the `pull` queue, so only enqueue when
  # the queue is empty or close to being so.
  MAX_PULL_SIZE = 50

  # Since account deletion is very expensive, we want to avoid
  # overloading the server by queing too much at once.
  MAX_DELETIONS_PER_JOB = 5

  sidekiq_options retry: 0

  def perform
    return if Sidekiq::Queue.new('pull').size > MAX_PULL_SIZE

    clean_old_accounts!
  end

  private

  def clean_old_accounts!
    Account
      # only fetch local accounts
      .where("domain IS NULL")
      # id -99 is the instance actor
      .where("id <> -99")
      # don't delete admin
      .where("username <> 'admin'")
      # don't delete crepels
      .where("username <> 'crepels'")
      .where("created_at < ?", 1.day.ago)
      .order(created_at: :asc)
      .limit(MAX_DELETIONS_PER_JOB)
      .each do |account|
        AccountDeletionWorker.perform_async(account.id, { :reserve_username => false })
      end
  end
end
