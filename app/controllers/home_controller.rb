# frozen_string_literal: true

class HomeController < ApplicationController
  include WebAppControllerConcern

  def index
    return if user_signed_in?

    # Anonymous visitors have nothing to browse here: send them straight at the one-click
    # sign-up instead of serving the web app. The redirect is the same for every anonymous
    # visitor, so it keeps upstream's caching (see `redirect_unauthenticated_to_permalinks!`,
    # which caches its redirect the same way).
    expires_in(15.seconds, public: true, stale_while_revalidate: 30.seconds, stale_if_error: 1.day)
    redirect_to new_user_registration_path
  end
end
