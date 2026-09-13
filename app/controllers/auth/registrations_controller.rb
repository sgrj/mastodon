# frozen_string_literal: true

require 'random_name_generator'
require 'securerandom'

class Auth::RegistrationsController < Devise::RegistrationsController
  include RegistrationHelper
  include Auth::RegistrationSpamConcern

  # ActivityPub.Academy accounts are throwaway teaching accounts: sign-up is one click,
  # with no username, e-mail or password field. The controller invents all three.
  ACADEMY_ACTOR_TYPE = 'Person'

  # v4.7 added `accounts.id_scheme` and defaults *new* rows to `numeric_ap_id`, which
  # publishes actor URIs as /ap/users/<id>. The Activity Log resolves its audience with
  # /users/<username> regexes, so under the default it is silently empty for every
  # account created after the upgrade. Pin the username scheme at creation time.
  ACADEMY_ID_SCHEME = 'username_ap_id'

  ROMAN_SYLLABLES = Rails.root.join('app', 'controllers', 'auth', 'roman.txt')

  FIRST_NAME_GENERATOR = RandomNameGenerator.new(File.new(ROMAN_SYLLABLES))
  LAST_NAME_GENERATOR  = RandomNameGenerator.new(RandomNameGenerator::FANTASY)

  # `RandomNameGenerator::Generator#compose` is not thread-safe: every call writes `@pre`
  # and draws from an unsynchronised `Random`, and both generators above are process-wide,
  # shared by every Puma thread. Composing a name takes microseconds and happens once per
  # sign-up, so one mutex around both calls costs nothing.
  NAME_GENERATOR_LOCK = Mutex.new

  layout :determine_layout

  before_action :set_invite, only: [:new, :create]
  before_action :check_enabled_registrations, only: [:new, :create]
  before_action :configure_sign_up_params, only: [:create]
  before_action :set_sessions, only: [:edit, :update]
  before_action :set_strikes, only: [:edit, :update]
  before_action :require_not_suspended!, only: [:update]
  before_action :set_rules, only: :new
  before_action :require_rules_acceptance!, only: :new
  before_action :set_registration_form_time, only: :new

  skip_before_action :check_self_destruct!, only: [:edit, :update]
  skip_before_action :require_functional!, only: [:edit, :update]

  def new
    super(&:build_invite_request)
  end

  def edit
    super
  end

  def create
    super
  end

  def update
    super do |resource|
      resource.clear_other_sessions(current_session.session_id) if resource.saved_change_to_encrypted_password?
    end
  end

  def destroy
    not_found
  end

  protected

  def update_resource(resource, params)
    params[:password] = nil if Devise.pam_authentication && resource.encrypted_password.blank?

    super
  end

  def build_resource(hash = nil)
    generate_academy_credentials!(hash) unless hash.nil?

    super

    resource.locale                 = I18n.locale
    resource.invite_code            = @invite&.code if resource.invite_code.blank?
    resource.registration_form_time = session[:registration_form_time]
    resource.sign_up_ip             = request.remote_ip

    resource.build_account if resource.account.nil?
  end

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up) do |user_params|
      user_params.permit({ account_attributes: [:username, :display_name], invite_request_attributes: [:text] }, :email, :password, :password_confirmation, :invite_code, :agreement, :website, :confirm_password, :date_of_birth)
    end
  end

  def after_sign_up_path_for(resource)
    # Visit the new user's own confirmation link instead of mailing it: the academy runs
    # without a mail server, and its accounts are disposable anyway.
    user_confirmation_path(confirmation_token: resource.confirmation_token)
  end

  def after_sign_in_path_for(_resource)
    set_invite

    if @invite&.autofollow?
      short_account_path(@invite.user.account)
    else
      super
    end
  end

  def after_inactive_sign_up_path_for(_resource)
    new_user_session_path
  end

  def after_update_path_for(_resource)
    edit_user_registration_path
  end

  def check_enabled_registrations
    redirect_to new_user_session_path, alert: I18n.t('devise.failure.closed_registrations', email: Setting.site_contact_email) unless allowed_registration?(request.remote_ip, @invite)
  end

  def invite_code
    if params[:user]
      params[:user][:invite_code]
    else
      params[:invite_code]
    end
  end

  private

  def set_invite
    @invite = begin
      invite = Invite.find_by(code: invite_code) if invite_code.present?
      invite if invite&.valid_for_use?
    end
  end

  def determine_layout
    case action_name
    when 'edit', 'update'
      'admin'
    when 'new'
      'academy-signup'
    else
      'auth'
    end
  end

  def generate_academy_credentials!(hash)
    display_name = generate_name
    username     = display_name.parameterize(separator: '_')
    password     = SecureRandom.hex

    # Written straight into the already-sanitised params, so these bypass
    # `configure_sign_up_params` entirely and nothing here needs permitting.
    hash['account_attributes'] = {
      'username' => username,
      'display_name' => display_name,
      'actor_type' => ACADEMY_ACTOR_TYPE,
      'id_scheme' => ACADEMY_ID_SCHEME,
    }
    hash['email'] = "#{username}@#{Rails.configuration.x.web_domain}"
    hash['password'] = password
    hash['password_confirmation'] = password
  end

  # On a name collision the student is shown "Something isn't quite right yet!" and signing
  # up again almost always succeeds. Collisions only start at ~1k accounts, and accounts are
  # deleted after a day, so this is not worth solving.
  def generate_name
    NAME_GENERATOR_LOCK.synchronize do
      "#{FIRST_NAME_GENERATOR.compose(3)} #{LAST_NAME_GENERATOR.compose(3)}"
    end
  end

  def set_sessions
    @sessions = current_user.session_activations.order(updated_at: :desc)
  end

  def set_strikes
    @strikes = current_account.strikes.recent.latest
  end

  def require_not_suspended!
    forbidden if current_account.unavailable?
  end

  def set_rules
    @rules = Rule.ordered.includes(:translations)
  end

  def require_rules_acceptance!
    return if @rules.empty? || validated_accept_token?

    @accept_token = session[:accept_token] = SecureRandom.hex
    @invite_code = invite_code
    @rule_translations = @rules.map { |rule| rule.translation_for(I18n.locale) }

    render :rules
  end

  def validated_accept_token?
    session[:accept_token].present? && params[:accept] == session[:accept_token]
  end

  def is_flashing_format? # rubocop:disable Naming/PredicatePrefix
    if params[:action] == 'create'
      false # Disable flash messages for sign-up
    else
      super
    end
  end
end
