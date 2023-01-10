# frozen_string_literal: true

class HomeController < ApplicationController
  include WebAppControllerConcern

  before_action :set_instance_presenter

  def index
    if !user_signed_in?
      redirect_to "/auth/sign_up"
    end
  end

  private

  def set_instance_presenter
    @instance_presenter = InstancePresenter.new
  end
end
