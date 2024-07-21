class AddCascadeDeleteToWebFingerOverridesAccount < ActiveRecord::Migration[6.1]
  def change
    # Remove the existing foreign key
    remove_foreign_key :web_finger_overrides, :accounts

    # Add the foreign key again with on_delete: :cascade
    add_foreign_key :web_finger_overrides, :accounts, on_delete: :cascade, validate: false
  end
end
