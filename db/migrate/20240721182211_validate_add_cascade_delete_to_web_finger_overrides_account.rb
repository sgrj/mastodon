class ValidateAddCascadeDeleteToWebFingerOverridesAccount < ActiveRecord::Migration[6.1]
  def change
    validate_foreign_key :web_finger_overrides, :accounts
  end
end
