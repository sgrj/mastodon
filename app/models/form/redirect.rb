# frozen_string_literal: true

class Form::Redirect
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Attributes::Normalization

  attr_accessor :account, :target_account, :current_password

  attribute :acct, :string
  attribute :current_username, :string

  validates :acct, presence: true, domain: { acct: true }
  validate :validate_target_account

  normalizes :acct, with: ->(value) { value.to_s.strip.gsub(/\A@/, '') }, apply_to_nil: true
  normalizes :current_username, with: ->(value) { value.strip.delete_prefix('@') }

  # No challenge: academy passwords are generated at sign-up and never shown to the
  # student, so there is nothing they could type back.
  def valid_with_challenge?(_current_user)
    set_target_account
    valid?
  end

  private

  def set_target_account
    @target_account = ResolveAccountService.new.call(acct, skip_cache: true)
  rescue Webfinger::Error, *Mastodon::HTTP_CONNECTION_ERRORS, Mastodon::Error, Addressable::URI::InvalidURIError
    # Validation will take care of it
  end

  def validate_target_account
    if target_account.nil?
      errors.add(:acct, I18n.t('migrations.errors.not_found'))
    else
      errors.add(:acct, I18n.t('migrations.errors.already_moved')) if account.moved? && account.moved_to_account_id == target_account.id
      errors.add(:acct, I18n.t('migrations.errors.move_to_self')) if account.id == target_account.id
    end
  end
end
