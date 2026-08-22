# frozen_string_literal: true
require 'redis'

class ActivityPub::InboxesController < ActivityPub::BaseController
  include SignatureVerification
  include JsonLdHelper
  include AccountOwnedConcern

  before_action :skip_unknown_actor_activity
  before_action :require_actor_signature!
  skip_before_action :authenticate_user!

  def create
    upgrade_account
    process_collection_synchronization
    process_payload
    head 202
  end

  private

  def skip_unknown_actor_activity
    head 202 if unknown_affected_account?
  end

  def unknown_affected_account?
    json = Oj.load(body, mode: :strict)
    json.is_a?(Hash) && %w(Delete Update).include?(json['type']) && json['actor'].present? && json['actor'] == value_or_id(json['object']) && !Account.where(uri: json['actor']).exists?
  rescue Oj::ParseError
    false
  end

  def account_required?
    params[:account_username].present?
  end

  def skip_temporary_suspension_response?
    true
  end

  def body
    return @body if defined?(@body)

    @body = request.body.read
    @body.force_encoding('UTF-8') if @body.present?

    request.body.rewind if request.body.respond_to?(:rewind)

    @body
  end

  def upgrade_account
    if signed_request_account&.ostatus?
      signed_request_account.update(last_webfingered_at: nil)
      ResolveAccountWorker.perform_async(signed_request_account.acct)
    end

    DeliveryFailureTracker.reset!(signed_request_actor.inbox_url)
  end

  def process_collection_synchronization
    raw_params = request.headers['Collection-Synchronization']
    return if raw_params.blank? || ENV['DISABLE_FOLLOWERS_SYNCHRONIZATION'] == 'true' || signed_request_account.nil?

    # Re-using the syntax for signature parameters
    tree   = SignatureParamsParser.new.parse(raw_params)
    params = SignatureParamsTransformer.new.apply(tree)

    ActivityPub::PrepareFollowersSynchronizationService.new.call(signed_request_account, params)
  rescue Parslet::ParseFailed
    Rails.logger.warn 'Error parsing Collection-Synchronization header'
  end

  def process_payload
    publish_activity_log_event

    ActivityPub::ProcessingWorker.perform_async(signed_request_actor.id, body, @account&.id, signed_request_actor.class.name)
  end

  # Reports the inbound activity to the Activity Log. This is observability on the hot
  # federation path, so it must not be able to reject a delivery that Mastodon would
  # otherwise have accepted.
  #
  # signed_request_actor is already actor_from_key_id(signature_params['keyId']) --
  # see SignatureVerification -- so there is no need to parse the Signature header a
  # second time to work out who sent this.
  def publish_activity_log_event
    activity_log_publisher.publish(
      ActivityLogEvent.new(
        'inbound',
        signed_request_actor&.uri,
        "https://#{Rails.configuration.x.web_domain}#{request.path}",
        Oj.load(body, mode: :strict)
      )
    )
  rescue => e
    Rails.logger.warn { "activity log: could not publish inbound event for #{request.path}: #{e.class}: #{e.message}" }
  end

  def activity_log_publisher
    @activity_log_publisher ||= ActivityLogPublisher.new
  end
end
