# frozen_string_literal: true

require 'rails_helper'

# ActivityPub.Academy sign-up is one click: the form carries no username, email or
# password fields, the controller generates all three, and the user is redirected
# straight at their own confirmation link so the instance needs no mail server.
describe 'Academy sign-up' do
  let(:web_domain) { Rails.configuration.x.web_domain }

  def sign_up(params = {})
    post user_registration_path, params: { user: { agreement: '1' }.merge(params) }
  end

  describe 'POST /auth' do
    it 'creates a user without being given any credentials' do
      expect { sign_up }.to change(User, :count).by(1)
    end

    it 'generates a username, display name and matching email' do
      sign_up

      account = User.last.account

      expect(account.username).to be_present
      expect(account.display_name).to be_present
      expect(User.last.email).to eq "#{account.username}@#{web_domain}"
    end

    # Scheduler::OldAccountCleanupScheduler deletes day-old accounts by matching
    # `username LIKE '%\_%'`, i.e. it identifies auto-generated accounts purely by the
    # underscore. If sign-up ever stopped producing one, ephemeral accounts would
    # silently stop being cleaned up.
    it 'generates a username containing an underscore, as the cleanup scheduler expects' do
      sign_up

      expect(User.last.account.username).to match(/\A[a-z0-9]+_[a-z0-9]+\z/)
    end

    it 'ignores any username, email and password the client submits' do
      sign_up(
        account_attributes: { username: 'chosen_name', display_name: 'Chosen' },
        email: 'attacker@example.com',
        password: 'hunter2hunter2',
        password_confirmation: 'hunter2hunter2'
      )

      user = User.last

      expect(user.account.username).to_not eq 'chosen_name'
      expect(user.email).to_not eq 'attacker@example.com'
      expect(user.valid_password?('hunter2hunter2')).to be false
    end

    it 'creates the account as a Person actor' do
      sign_up

      expect(User.last.account.actor_type).to eq 'Person'
    end

    it 'redirects to the user\'s own confirmation link' do
      sign_up

      expect(response).to redirect_to "/auth/confirmation?confirmation_token=#{User.last.confirmation_token}"
    end
  end

  describe 'the confirmation redirect' do
    it 'confirms the account without any email being sent' do
      sign_up
      user = User.last

      expect(user.confirmed?).to be false

      expect { get response.headers['Location'] }
        .to change { user.reload.confirmed? }.from(false).to(true)
    end
  end

  # The honeypot timer was relaxed from upstream's 3 seconds to 0.5 (see
  # app/validators/registration_form_time_validator.rb) so the one-click flow isn't
  # rejected as a bot.
  describe 'registration form timing' do
    before { get new_user_registration_path }

    it 'rejects a submission made instantly' do
      expect { sign_up }.to_not change(User, :count)
    end

    it 'accepts a submission made after the minimum form time' do
      # travel_to truncates sub-second precision, so a one-second jump can land less
      # than the 0.5s threshold away from the form time.
      travel_to(2.seconds.from_now) do
        expect { sign_up }.to change(User, :count).by(1)
      end
    end
  end

  describe 'signed-out browsing' do
    it 'sends an anonymous visitor from / to the sign-up page' do
      get root_path

      expect(response).to redirect_to '/auth/sign_up'
    end

    it 'serves the sign-up page' do
      get new_user_registration_path

      expect(response).to have_http_status(200)
    end
  end

  describe 'signing out' do
    it 'returns to the sign-up page rather than a sign-in form' do
      sign_up

      delete destroy_user_session_path

      expect(response).to redirect_to '/auth/sign_up'
    end
  end
end
