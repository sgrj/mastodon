# frozen_string_literal: true

# Backs the Activity Workshop: delivers a hand-crafted activity, signed as the current
# account, to any inbox. The activity is deliberately not validated -- seeing what a
# receiving server does with a malformed activity is the point of the exercise.
class Api::V1::ActivityController < Api::BaseController
  # config/initializers/wrap_parameters.rb wraps JSON bodies under a key derived from
  # the controller name -- which here is `activity`, exactly this endpoint's own
  # parameter. The wrapper only fires when that key is *absent*, so it is inert for a
  # well-formed request and, for a malformed one, silently invents an activity out of
  # whatever else was in the body (`{"inbox_url": "..."}` becomes the activity) and
  # signs and delivers it. `params.require(:activity)` has to mean what it says on an
  # endpoint that emits federation traffic as the student, so wrapping is off here.
  wrap_parameters false

  before_action :require_user!

  def create
    ActivityPub::DeliveryWorker.perform_async(
      activity_params[:activity].to_h.to_json,
      current_account.id,
      activity_params[:inbox_url]
    )

    render json: true
  end

  private

  def activity_params
    params.require(:inbox_url)
    params.require(:activity)

    # `activity: {}` permits the arbitrary nested activity object wholesale. Verified
    # under Rails 8.1: the wildcard still lets nested objects and arrays through at any
    # depth, and still preserves JSON scalars (integers, booleans, null) when the
    # request arrives as application/json -- which is how the SPA sends it.
    #
    # A non-hash `activity` (a bare string, an array) is not a match for the filter, so
    # permit drops it and the delivered body becomes `{}`. That is the one shape the
    # Workshop cannot produce: the body handed to DeliveryWorker is always syntactically
    # valid JSON. See Surprise 31 in PORTING.md.
    params.permit(:inbox_url, activity: {})
  end
end
