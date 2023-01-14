# frozen_string_literal: true

class Form::Redirect
  include ActiveModel::Model

  attr_accessor :account, :target_account, :current_password,
                :current_username

  attr_reader :acct

  validates :acct, presence: true, domain: { acct: true }
  validate :validate_target_account

  def valid_with_challenge?(current_user)
    set_target_account
    valid?
  end

  def acct=(val)
    @acct = val.to_s.strip.gsub(/\A@/, '')
  end

  private

  def set_target_account
    @target_account = ResolveAccountService.new.call(acct, skip_cache: true)
  rescue Webfinger::Error, HTTP::Error, OpenSSL::SSL::SSLError, Mastodon::Error, Addressable::URI::InvalidURIError
    # Validation will take care of it
  end

  def validate_target_account
    if target_account.nil?
      errors.add(:acct, I18n.t('migrations.errors.not_found'))
    else
      errors.add(:acct, I18n.t('migrations.errors.already_moved')) if account.moved_to_account_id.present? && account.moved_to_account_id == target_account.id
      errors.add(:acct, I18n.t('migrations.errors.move_to_self')) if account.id == target_account.id
    end
  end
end
