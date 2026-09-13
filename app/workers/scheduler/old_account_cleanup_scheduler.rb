# frozen_string_literal: true

# The academy is a throwaway instance: Auth::RegistrationsController mints a whole
# account on one click, so without a reaper the database accumulates every actor any
# student ever generated. This deletes them a day later.
class Scheduler::OldAccountCleanupScheduler
  include Sidekiq::Worker

  # Each processed deletion may enqueue an enormous amount of jobs in the `pull`
  # queue, so only enqueue when the queue is empty or close to being so.
  MAX_PULL_SIZE = 50

  # Since account deletion is very expensive, we want to avoid overloading the
  # server by queuing too much at once.
  MAX_DELETIONS_PER_JOB = 5

  MAX_AGE = 1.day

  # The only thing separating a generated account from a real one. Cluster 4 builds
  # every academy username as `"First Last".parameterize(separator: '_')`, so a
  # generated account always contains an underscore and a hand-made one (`alice`, the
  # maintainer's own) never does.
  #
  # The backslash is load-bearing: a bare `_` is LIKE's single-character wildcard, so
  # `'%_%'` matches every username of length one or more -- every account on the
  # instance. PostgreSQL's default escape character for LIKE is `\`, and with
  # `standard_conforming_strings` on (the default since 9.1) a single-quoted Ruby
  # string passes it through untouched. Verified against this instance's PostgreSQL
  # 14.6, both as a literal and as a bind parameter.
  GENERATED_USERNAME_PATTERN = '%\_%'

  sidekiq_options retry: 0

  def perform
    return if Sidekiq::Queue.new('pull').size > MAX_PULL_SIZE

    clean_old_accounts!
  end

  private

  def clean_old_accounts!
    old_generated_accounts.each do |account|
      # Since v4.2 `AccountDeletionWorker` returns without doing anything unless the
      # account is already unavailable, so enqueueing it against a live account is a
      # silent no-op. Every other caller marks the account first; this is the same
      # `mark_deleted!` that Settings::DeletesController uses for a self-deletion,
      # which is also what this is -- a deletion on the student's behalf, not a
      # moderation action, so no suspension and no canonical e-mail block.
      #
      # It also makes the job idempotent: a marked account leaves `without_suspended`,
      # so a backed-up `pull` queue cannot make the next run mark it twice.
      account.mark_deleted!
      AccountDeletionWorker.perform_async(account.id, { 'reserve_username' => false })
    end
  end

  def old_generated_accounts
    Account
      .local
      .without_instance_actor
      .without_suspended
      .where('username LIKE ?', GENERATED_USERNAME_PATTERN)
      .where(created_at: ...MAX_AGE.ago)
      .order(created_at: :asc)
      .limit(MAX_DELETIONS_PER_JOB)
  end
end
