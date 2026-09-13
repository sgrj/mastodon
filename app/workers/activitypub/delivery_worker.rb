# frozen_string_literal: true

class ActivityPub::DeliveryWorker
  include Sidekiq::Worker
  include RoutingHelper
  include JsonLdHelper

  STOPLIGHT_COOL_OFF_TIME = 60
  STOPLIGHT_FAILURE_THRESHOLD = 10

  # retry: 0 is a fork change, and a real one: an outbound delivery that fails is not
  # retried at all. Every attempt publishes its own Activity Log entry, so upstream's
  # 16 retries would replay the same failure into a student's log for days. The
  # subclasses that genuinely depend on redelivery set their own value
  # (ActivityPub::LowPriorityDeliveryWorker is retry: 8).
  sidekiq_options queue: 'push', retry: 0, dead: false

  # Unfortunately, we cannot control Sidekiq's jitter, so add our own
  sidekiq_retry_in do |count|
    # This is Sidekiq's default delay
    delay  = (count**4) + 15
    # Our custom jitter, that will be added to Sidekiq's built-in one.
    # Sidekiq's built-in jitter is `rand(10) * (count + 1)`
    jitter = rand(0.5 * (count**4))
    delay + jitter
  end

  HEADERS = { 'Content-Type' => 'application/activity+json' }.freeze

  def perform(json, source_account_id, inbox_url, options = {})
    @options        = options.with_indifferent_access

    return unless @options[:bypass_availability] || DeliveryFailureTracker.available?(inbox_url)

    @json           = json
    @source_account = Account.find(source_account_id)
    @inbox_url      = inbox_url
    @host           = Addressable::URI.parse(inbox_url).normalized_site
    @performed      = false
    @failure        = nil

    perform_request
  rescue => e
    # Record the failure for the Activity Log, then let it propagate. The ensure block
    # below publishes the event before the exception leaves this method, so the student
    # still sees the failure -- but Sidekiq sees it too. That matters for the
    # subclasses: LowPriorityDeliveryWorker declares retry: 8, and
    # MigratedFollowDeliveryWorker only unfollows the old account once the Follow has
    # actually been delivered to the new one.
    @failure = e.message
    raise
  ensure
    publish_activity_log_event(json, inbox_url)

    if @inbox_url.present?
      if @performed
        failure_tracker.track_success!
      elsif !@unsalvageable
        failure_tracker.track_failure!
      end
    end
  end

  private

  def build_request(http_client)
    Request.new(:post, @inbox_url, body: @json, http_client: http_client).tap do |request|
      request.on_behalf_of(@source_account, sign_with: sign_with)
      request.add_headers(HEADERS)
      request.add_headers({ 'Collection-Synchronization' => synchronization_header }) if ENV['DISABLE_FOLLOWERS_SYNCHRONIZATION'] != 'true' && @options[:synchronize_followers]
    end
  end

  def synchronization_header
    "collectionId=\"#{ActivityPub::TagManager.instance.followers_uri_for(@source_account)}\", digest=\"#{@source_account.remote_followers_hash(@inbox_url)}\", url=\"#{account_followers_synchronization_url(@source_account)}\""
  end

  def perform_request
    stoplight_wrapper.run do
      request_pool.with(@host) do |http_client|
        build_request(http_client).perform do |response|
          if response_successful?(response)
            @performed = true
          else
            # Recorded before the salvageable/unsalvageable split on purpose. An
            # unsalvageable 401 or 410 is never retried, so this is the only chance a
            # student gets to see why their activity did not arrive -- and showing them
            # that is the point of the Activity Log.
            @failure = "#{@inbox_url} responded with status #{response.status}"

            if response_error_unsalvageable?(response) || unsalvageable_authorization_failure?(response)
              @unsalvageable = true
            else
              raise Mastodon::UnexpectedResponseError, response
            end
          end
        end
      end
    end
  end

  def unsalvageable_authorization_failure?(response)
    @source_account.permanently_unavailable? && response.code == 401
  end

  def stoplight_wrapper
    Stoplight(
      @inbox_url,
      cool_off_time: STOPLIGHT_COOL_OFF_TIME,
      threshold: STOPLIGHT_FAILURE_THRESHOLD
    )
  end

  def failure_tracker
    @failure_tracker ||= DeliveryFailureTracker.new(@inbox_url)
  end

  def request_pool
    RequestPool.current
  end

  def sign_with
    @options[:sign_with].presence && Keypair.from_worker_arg(@source_account, @options[:sign_with])
  end

  def activity_log_publisher
    @activity_log_publisher ||= ActivityLogPublisher.new
  end

  # Reporting to the Activity Log is observability: it must never turn a delivery into
  # a failure. It runs from an ensure block, so it also runs on the early return, when
  # no source account has been loaded.
  def publish_activity_log_event(json, inbox_url)
    return if @source_account.nil?

    activity_log_publisher.publish(
      ActivityLogEvent.new(
        'outbound',
        ActivityPub::TagManager.instance.uri_for(@source_account),
        inbox_url,
        JSON.parse(json),
        @failure
      )
    )
  rescue => e
    Rails.logger.warn { "activity log: could not publish outbound event for #{inbox_url}: #{e.class}: #{e.message}" }
  end
end
