# == Schema Information
#
# Table name: authorization_requests
#
#  id                :bigint           not null, primary key
#  completed_at      :datetime
#  consumed_at       :datetime
#  identity_response :jsonb
#  idv_rec           :string
#  popup_url         :string
#  program           :string           not null
#  status            :string           default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  auth_id           :string           not null
#
# Indexes
#
#  index_authorization_requests_on_auth_id             (auth_id) UNIQUE
#  index_authorization_requests_on_consumed_at         (consumed_at)
#  index_authorization_requests_on_created_at          (created_at)
#  index_authorization_requests_on_program_and_status  (program,status)
#
class AuthorizationRequest < ApplicationRecord
  validates :auth_id, presence: true, uniqueness: true
  validates :program, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending completed failed expired] }

  belongs_to :program_record, class_name: 'Program', primary_key: 'slug', foreign_key: 'program', optional: true

  scope :pending, -> { where(status: 'pending') }
  scope :completed, -> { where(status: 'completed') }
  scope :recent, -> { order(created_at: :desc) }

  def complete!(idv_rec)
    update!(
      status: 'completed',
      idv_rec: idv_rec,
      completed_at: Time.current
    )
  end

  def expire!
    update!(status: 'expired') if pending?
  end

  def completed?
    status == 'completed'
  end

  def pending?
    status == 'pending'
  end
end
