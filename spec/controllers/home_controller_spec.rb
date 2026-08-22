require 'rails_helper'

RSpec.describe HomeController, type: :controller do
  render_views

  describe 'GET #index' do
    subject { get :index }

    context 'when not signed in' do
      it 'returns http success', academy: :disabled,
                                 reason: 'the fork redirects anonymous visitors from / to /auth/sign_up rather than rendering the landing page (HomeController#index)' do
        @request.path = '/'
        is_expected.to have_http_status(:success)
      end

      it 'redirects to the academy sign-up page' do
        @request.path = '/'
        is_expected.to redirect_to '/auth/sign_up'
      end
    end

    context 'when signed in' do
      let(:user) { Fabricate(:user) }

      before do
        sign_in(user)
      end

      it 'returns http success' do
        is_expected.to have_http_status(:success)
      end
    end
  end
end
