# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Home page' do
  context 'when signed in' do
    before { sign_in Fabricate(:user) }

    it 'visits the homepage and renders the web app' do
      visit root_path

      expect(page)
        .to have_css('noscript', text: /Mastodon/)
        .and have_css('body', class: 'app-body')
      expect(find('.app-holder#mastodon')['data-props'])
        .to eq('{"locale":"en"}')
    end
  end

  context 'when not signed in' do
    it 'visits the homepage and renders the web app', academy: :disabled,
                                                      reason: 'the fork redirects anonymous visitors from / to /auth/sign_up rather than serving the web app, so nothing renders for a logged-out browser (HomeController#index)' do
      visit root_path

      expect(page)
        .to have_css('noscript', text: /Mastodon/)
        .and have_css('body', class: 'app-body')
    end

    it 'visits the homepage and is sent to the academy sign-up page' do
      visit root_path

      expect(page).to have_current_path('/auth/sign_up')
    end

    context 'when the landing page is set to about' do
      before do
        Setting.landing_page = 'about'
      end

      it 'visits the root path and is redirected to the about page', :js, academy: :disabled,
                                                                          reason: 'the fork redirects anonymous visitors from / to /auth/sign_up before the JS app loads, and the landing-page setting is only applied by the JS app (HomeController#index)' do
        visit root_path

        expect(page).to have_current_path('/about')
      end
    end

    context 'when the landing page is set to trends' do
      before do
        Setting.landing_page = 'trends'
      end

      it 'visits the root path and is redirected to the trends page', :js do
        visit root_path

        expect(page).to have_current_path('/explore')
      end
    end

    context 'when the landing page is set to local_feed' do
      before do
        Setting.landing_page = 'local_feed'
      end

      it 'visits the root path and is redirected to the local live feed page', :js do
        visit root_path

        expect(page).to have_current_path('/public/local')
      end
    end
  end
end
