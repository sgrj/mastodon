# frozen_string_literal: true

# Backs the WebFinger Forge: lets a student replace the WebFinger document served for
# their own actor, so they can see what discovery lying to remote servers does.
class Api::V1::WebfingerController < Api::BaseController
  before_action :require_user!

  rescue_from Oj::ParseError, EncodingError, with: :invalid_json

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
    # /.well-known/webfinger, so it has to actually parse. Oj.dump would serialize the
    # string rather than parse it, and so could never reject anything.
    Oj.load(webfinger_params[:value], mode: :strict)

    override = WebFingerOverride.find_or_initialize_by(account_id: current_account.id)
    override.value = webfinger_params[:value]
    override.save!

    head :no_content
  end

  private

  def webfinger_params
    params.permit(:value)
  end

  def invalid_json
    render json: { error: 'Value must be valid JSON' }, status: 422
  end
end
