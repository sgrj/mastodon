class CreateWebFingerOverrides < ActiveRecord::Migration[6.1]
  def change
    create_table :web_finger_overrides do |t|
      t.text :value
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
