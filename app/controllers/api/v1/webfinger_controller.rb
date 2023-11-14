# frozen_string_literal: true

class Api::V1::WebfingerController < Api::BaseController
  include ActionController::Live

  before_action :require_user!

  def create
    # make sure that value is valid json
    Oj.dump(webfinger_params[:value])
    override = WebFingerOverride.find_or_create_by(account_id: current_account.id)
    override.value = webfinger_params[:value]
    override.save!
  end

  def show
    override = WebFingerOverride.find_by(account_id: current_account.id)
      if (override.nil?)
        render json: current_account, serializer: WebfingerSerializer, content_type: 'application/jrd+json'
      else
        render json: override.value, content_type: 'application/jrd+json'
      end
  end

  def webfinger_params
    params.permit(:value)
  end
end
