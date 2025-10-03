# == Schema Information
#
# Table name: user_journey_events
#
#  id                      :bigint           not null, primary key
#  email                   :string
#  event_type              :string           not null
#  idv_rec                 :string
#  metadata                :jsonb
#  program                 :string
#  request_ip              :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  verification_attempt_id :bigint
#
# Indexes
#
#  index_user_journey_events_on_created_at               (created_at)
#  index_user_journey_events_on_email                    (email)
#  index_user_journey_events_on_event_type               (event_type)
#  index_user_journey_events_on_idv_rec                  (idv_rec)
#  index_user_journey_events_on_program                  (program)
#  index_user_journey_events_on_verification_attempt_id  (verification_attempt_id)
#
# Foreign Keys
#
#  fk_rails_...  (verification_attempt_id => verification_attempts.id)
#
class UserJourneyEvent < ApplicationRecord
  belongs_to :verification_attempt, optional: true

  # event_type: string, e.g. 'program_page', 'oauth_start', 'oauth_callback', 'verification_attempt'
  # program: string
  # idv_rec: string
  # email: string
  # request_ip: string
  # metadata: jsonb
  # verification_attempt_id: integer (optional)
end
