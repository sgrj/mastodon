# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Log Out' do
  include RoutingHelper

  describe 'DELETE /auth/sign_out' do
    let(:user) { Fabricate(:user) }

    before do
      sign_in user
    end

    it 'Logs out the user and redirect', academy: :disabled,
                                         reason: 'the fork sends signed-out users to /auth/sign_up rather than the sign-in form, because academy accounts are one-click and disposable (ApplicationController#after_sign_out_path_for)' do
      delete '/auth/sign_out'

      expect(response).to redirect_to('/auth/sign_in')
    end

    it 'Logs out the user and redirects to the academy sign-up page' do
      delete '/auth/sign_out'

      expect(response).to redirect_to('/auth/sign_up')
    end

    it 'Logs out the user and return a page to redirect to with a JSON request', academy: :disabled,
                                                                                 reason: 'the fork sends signed-out users to /auth/sign_up rather than the sign-in form, because academy accounts are one-click and disposable (ApplicationController#after_sign_out_path_for)' do
      delete '/auth/sign_out', headers: { 'HTTP_ACCEPT' => 'application/json' }

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq 'application/json'

      expect(response.parsed_body[:redirect_to]).to eq '/auth/sign_in'
    end

    it 'Logs out the user and returns the academy sign-up page with a JSON request' do
      delete '/auth/sign_out', headers: { 'HTTP_ACCEPT' => 'application/json' }

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq 'application/json'

      expect(response.parsed_body[:redirect_to]).to eq '/auth/sign_up'
    end
  end
end
