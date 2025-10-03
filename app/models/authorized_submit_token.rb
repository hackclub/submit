# == Schema Information
#
# Table name: authorized_submit_tokens
#
#  id         :bigint           not null, primary key
#  idv_rec    :string           not null
#  issued_at  :datetime         not null
#  program    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  submit_id  :string           not null
#
# Indexes
#
#  index_authorized_submit_tokens_on_idv_rec    (idv_rec)
#  index_authorized_submit_tokens_on_program    (program)
#  index_authorized_submit_tokens_on_submit_id  (submit_id) UNIQUE
#
class AuthorizedSubmitToken < ApplicationRecord
  validates :submit_id, presence: true, uniqueness: true
  validates :idv_rec, presence: true

  # Mark token as used (delete) to prevent reuse after verification attempt
  def consume!
    destroy!
  rescue => _
    # no-op; best-effort consumption
  end
end
