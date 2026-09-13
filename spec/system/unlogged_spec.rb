# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'UnloggedBrowsing', :js, :streaming, academy: :disabled,
                                                    reason: 'the fork redirects anonymous visitors from / to /auth/sign_up rather than serving the web app, so nothing renders for a logged-out browser (HomeController#index)' do
  subject { page }

  before do
    visit root_path
  end

  it 'loads the home page' do
    expect(subject).to have_css('div.app-holder')

    expect(subject).to have_css('main.columns-area__panels__main')
  end
end
