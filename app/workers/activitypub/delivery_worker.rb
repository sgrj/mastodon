# frozen_string_literal: true

class ActivityPub::DeliveryWorker
  include Sidekiq::Worker
  include RoutingHelper
  include JsonLdHelper

  STOPLIGHT_FAILURE_THRESHOLD = 10
  STOPLIGHT_COOLDOWN = 60

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
      else
        failure_tracker.track_failure!
      end
    end
  end

  private

  def build_request(http_client)
    Request.new(:post, @inbox_url, body: @json, http_client: http_client).tap do |request|
      request.on_behalf_of(@source_account, sign_with: @options[:sign_with])
      request.add_headers(HEADERS)
      request.add_headers({ 'Collection-Synchronization' => synchronization_header }) if ENV['DISABLE_FOLLOWERS_SYNCHRONIZATION'] != 'true' && @options[:synchronize_followers]
    end
  end

  def synchronization_header
    "collectionId=\"#{account_followers_url(@source_account)}\", digest=\"#{@source_account.remote_followers_hash(@inbox_url)}\", url=\"#{account_followers_synchronization_url(@source_account)}\""
  end

  def perform_request
    light = Stoplight(@inbox_url) do
      request_pool.with(@host) do |http_client|
        build_request(http_client).perform do |response|
          if !response_successful?(response)
            @failure = "#{@inbox_url} responded with status #{response.status}"
          end
          raise Mastodon::UnexpectedResponseError, response unless response_successful?(response) || response_error_unsalvageable?(response)

          @performed = true
        end
      end
    end

    light.with_threshold(STOPLIGHT_FAILURE_THRESHOLD)
         .with_cool_off_time(STOPLIGHT_COOLDOWN)
         .run
  end

  def failure_tracker
    @failure_tracker ||= DeliveryFailureTracker.new(@inbox_url)
  end

  def request_pool
    RequestPool.current
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
        "https://#{Rails.configuration.x.web_domain}/users/#{@source_account.username}",
        inbox_url,
        Oj.load(json, mode: :strict),
        @failure
      )
    )
  rescue => e
    Rails.logger.warn { "activity log: could not publish outbound event for #{inbox_url}: #{e.class}: #{e.message}" }
  end
end
