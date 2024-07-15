# == Schema Information
#
# Table name: web_finger_overrides
#
#  id         :bigint(8)        not null, primary key
#  value      :text
#  account_id :bigint(8)        not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class WebFingerOverride < ApplicationRecord
  belongs_to :account
end
