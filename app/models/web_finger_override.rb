# frozen_string_literal: true

# == Schema Information
#
# Table name: web_finger_overrides
#
#  id         :bigint(8)        not null, primary key
#  value      :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#

# Backs the WebFinger Forge: an arbitrary JRD blob a student stores for their own
# account, served verbatim from /.well-known/webfinger in place of the document
# WebfingerSerializer would have produced. Deliberately unvalidated beyond "is JSON" --
# letting discovery lie is the lesson.
class WebFingerOverride < ApplicationRecord
  belongs_to :account
end
