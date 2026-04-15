require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  include OmniAuthTestHelper

  setup do
    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth
  end

  teardown do
    OmniAuth.config.mock_auth[:hack_club] = nil
  end

  # --- User flow ---

  test "user flow redirects to form on successful auth" do
    # Set up session context by hitting the start endpoint first
    get "/identity/start", params: { program: 'test-program' }
    assert_redirected_to '/auth/hack_club'

    # Simulate OmniAuth callback
    get "/auth/hack_club/callback"
    assert_response :redirect
    location = response.location
    form_host = URI.parse(programs(:test_program).form_url).host
    assert_equal form_host, URI.parse(location).host, "Expected redirect to program form host, got: #{location}"
  end

  test "user flow rejects unverified users" do
    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth(
      'verification_status' => 'pending'
    )

    get "/identity/start", params: { program: 'test-program' }
    get "/auth/hack_club/callback"
    assert_redirected_to root_path
    assert_equal 'Your identity verification is pending. Please wait for approval.', flash[:alert]
  end

  test "user flow rejects rejected users" do
    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth(
      'rejection_reason' => 'fraud'
    )

    get "/identity/start", params: { program: 'test-program' }
    get "/auth/hack_club/callback"
    assert_redirected_to root_path
    assert_includes flash[:alert], 'rejected'
  end

  test "user flow rejects users over 18" do
    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth(
      'ysws_eligible' => false
    )

    get "/identity/start", params: { program: 'test-program' }
    get "/auth/hack_club/callback"
    assert_redirected_to root_path
    assert_includes flash[:alert], '18 and under'
  end

  test "user flow creates authorized submit token" do
    get "/identity/start", params: { program: 'test-program' }
    assert_difference 'AuthorizedSubmitToken.count', 1 do
      get "/auth/hack_club/callback"
    end
  end

  # --- Admin flow ---

  test "admin flow logs in valid admin" do
    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth(
      'email' => 'admin@example.com'
    )

    get "/admin/login"
    assert_redirected_to '/auth/hack_club'

    get "/auth/hack_club/callback"
    assert_redirected_to admin_root_path
    assert_equal 'Welcome back!', flash[:success]
  end

  test "admin flow redirects ysws_author to programs" do
    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth(
      'email' => 'author@example.com'
    )

    get "/admin/login"
    get "/auth/hack_club/callback"
    assert_redirected_to admin_programs_path
  end

  test "admin flow rejects non-admin email" do
    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth(
      'email' => 'nobody@example.com'
    )

    get "/admin/login"
    get "/auth/hack_club/callback"
    assert_redirected_to root_path
    assert_equal 'Unauthorized', flash[:alert]
  end

  # --- Popup flow ---

  test "popup flow completes authorization request" do
    auth_request = authorization_requests(:pending_request)

    # Visit the popup page to set up session context
    get "/popup/authorize/#{auth_request.auth_id}"
    assert_response :success

    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth

    get "/auth/hack_club/callback"
    assert_response :success # renders success template

    auth_request.reload
    assert_equal 'completed', auth_request.status
    assert_equal 'ident!abc123', auth_request.idv_rec
  end

  test "popup flow rejects unverified users" do
    auth_request = authorization_requests(:pending_request)

    get "/popup/authorize/#{auth_request.auth_id}"

    OmniAuth.config.mock_auth[:hack_club] = mock_hack_club_auth(
      'verification_status' => 'pending'
    )

    get "/auth/hack_club/callback"
    assert_response :success # renders error template
    assert_includes response.body, 'pending'
  end

  # --- Failure ---

  test "failure redirects with error message" do
    get "/auth/failure", params: { message: 'invalid_credentials' }
    assert_redirected_to root_path
    assert_includes flash[:alert], 'invalid_credentials'
  end

  test "missing context redirects to root" do
    # Hit callback without setting up context first
    get "/auth/hack_club/callback"
    assert_redirected_to root_path
  end
end
