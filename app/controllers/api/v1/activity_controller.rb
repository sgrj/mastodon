# frozen_string_literal: true

# Backs the Activity Workshop: delivers a hand-crafted activity, signed as the current
# account, to any inbox. The activity is deliberately not validated -- seeing what a
# receiving server does with a malformed activity is the point of the exercise.
class Api::V1::ActivityController < Api::BaseController
  before_action :require_user!

  def create
    ActivityPub::DeliveryWorker.perform_async(
      Oj.dump(activity_params[:activity].to_h),
      current_account.id,
      activity_params[:inbox_url]
    )

    render json: true
  end

  private

  def activity_params
    params.require(:inbox_url)
    params.require(:activity)

    # `activity: {}` permits the arbitrary nested activity object wholesale.
    params.permit(:inbox_url, activity: {})
  end
end
