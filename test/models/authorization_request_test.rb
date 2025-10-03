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
require "test_helper"

class AuthorizationRequestTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
