# == Schema Information
#
# Table name: verification_attempts
#
#  id                  :bigint           not null, primary key
#  email               :string
#  first_name          :string
#  identity_response   :jsonb
#  idv_rec             :string
#  ip                  :string
#  last_name           :string
#  program             :string
#  rejection_reason    :string
#  verification_status :string
#  verified            :boolean          default(FALSE), not null
#  ysws_eligible       :boolean
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  submit_id           :string
#
# Indexes
#
#  index_verification_attempts_on_created_at        (created_at)
#  index_verification_attempts_on_email             (email)
#  index_verification_attempts_on_idv_rec           (idv_rec)
#  index_verification_attempts_on_program           (program)
#  index_verification_attempts_on_submit_id_unique  (submit_id) UNIQUE WHERE (submit_id IS NOT NULL)
#  index_verification_attempts_on_verified          (verified)
#
class VerificationAttempt < ApplicationRecord
	# Uncomment validations if you want to enforce presence
	# validates :idv_rec, :email, presence: true

	def self.loggable_attributes
		column_names
	end

	# Optional: return combined idv:submit string for display/export
	def combined_identity
		return nil if idv_rec.blank? && submit_id.blank?
		[idv_rec, submit_id].compact.join(':')
	end
end
