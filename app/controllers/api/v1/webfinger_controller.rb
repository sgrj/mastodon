# frozen_string_literal: true

# Backs the WebFinger Forge: lets a student replace the WebFinger document served for
# their own actor, so they can see what discovery lying to remote servers does.
class Api::V1::WebfingerController < Api::BaseController
  before_action :require_user!

  rescue_from JSON::ParserError, EncodingError, with: :invalid_json

  def show
    override = WebFingerOverride.find_by(account_id: current_account.id)

    if override.nil?
      render json: current_account, serializer: WebfingerSerializer, content_type: 'application/jrd+json'
    else
      render json: override.value, content_type: 'application/jrd+json'
    end
  end

  def create
    # The value is stored verbatim and later served as application/jrd+json from
    # /.well-known/webfinger, so it has to actually parse. This must *parse* the string:
    # serialising it instead (`.to_json`) would wrap any input in quotes and so could
    # never reject anything. Well-formed nonsense is deliberately allowed through --
    # that is the lesson.
    JSON.parse(webfinger_params[:value].to_s)

    override = WebFingerOverride.find_or_initialize_by(account_id: current_account.id)
    override.value = webfinger_params[:value]
    override.save!

    head 204
  end

  private

  def webfinger_params
    params.permit(:value)
  end

  def invalid_json
    render json: { error: 'Value must be valid JSON' }, status: 422
  end
end
