require "test_helper"

class IdentityControllerTest < ActionDispatch::IntegrationTest
  test "url endpoint requires program param" do
    get "/api/identity/url"
    assert_response :bad_request
    assert_includes response.parsed_body['error'], 'Program parameter required'
  end

  test "url endpoint returns 404 for unknown program" do
    get "/api/identity/url", params: { program: 'nonexistent' }
    assert_response :not_found
  end

  test "url endpoint returns 403 for inactive program" do
    get "/api/identity/url", params: { program: 'inactive-program' }
    assert_response :forbidden
  end

  test "url endpoint returns auth url and stores session context" do
    get "/api/identity/url", params: { program: 'test-program' }
    assert_response :success
    body = response.parsed_body
    assert body['url'].include?('/auth/hack_club'), "Expected URL to point to /auth/hack_club, got: #{body['url']}"
  end

  test "start redirects to omniauth for valid program" do
    get "/identity/start", params: { program: 'test-program' }
    assert_redirected_to '/auth/hack_club'
  end

  test "start rejects missing program" do
    get "/identity/start"
    assert_redirected_to root_path
  end

  test "start rejects inactive program" do
    get "/identity/start", params: { program: 'inactive-program' }
    assert_redirected_to root_path
  end
end
