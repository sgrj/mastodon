# frozen_string_literal: true

class Api::V1::ActivityController < Api::BaseController
  before_action :authenticate_user!

  def create
    ActivityPub::DeliveryWorker.perform_async(Oj.dump(activity_params[:activity]), current_account.id, activity_params[:inbox_url])

    # to allow sending of activities without a user (to develop the frontend),
    # uncomment the following line, and comment the authenticate_user before_action
    # ActivityPub::DeliveryWorker.perform_async(Oj.dump(activity_params[:activity]), 110819192012359728, activity_params[:inbox_url])
    render json: true
  end


  # TODO: require inbox_url and activity
  def activity_params
    # params.permit(:inbox_url, :activity)
    params
  end
end
