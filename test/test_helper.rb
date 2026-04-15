ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  fixtures :all
end

# OmniAuth test mode — prevents real HTTP requests during tests
OmniAuth.config.test_mode = true

# Helper to build a mock OmniAuth auth hash
module OmniAuthTestHelper
  def mock_hack_club_auth(identity = {})
    defaults = {
      'id' => 'ident!abc123',
      'email' => 'ada@example.com',
      'first_name' => 'Ada',
      'last_name' => 'Lovelace',
      'full_name' => 'Ada Lovelace',
      'verification_status' => 'verified',
      'ysws_eligible' => true,
      'slack_id' => 'U12345678'
    }
    merged = defaults.merge(identity)

    OmniAuth::AuthHash.new(
      provider: 'hack_club',
      uid: merged['id'],
      info: {
        email: merged['email'],
        first_name: merged['first_name'],
        last_name: merged['last_name'],
        name: "#{merged['first_name']} #{merged['last_name']}",
        slack_id: merged['slack_id'],
        verification_status: merged['verification_status']
      },
      credentials: {
        token: 'mock_token',
        expires_at: 1.hour.from_now.to_i,
        expires: true
      },
      extra: {
        raw_info: { 'identity' => merged }
      }
    )
  end
end
