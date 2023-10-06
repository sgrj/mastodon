# frozen_string_literal: true

class Api::V1::ActivityController < Api::BaseController
  before_action :authenticate_user!

  def create
    render json: current_account
  end
end
