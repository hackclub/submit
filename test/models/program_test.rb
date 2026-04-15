require "test_helper"

class ProgramTest < ActiveSupport::TestCase
  test "oauth_scopes always includes openid and verification_status" do
    program = programs(:test_program)
    scopes = program.oauth_scopes.split(' ')
    assert_includes scopes, 'openid'
    assert_includes scopes, 'verification_status'
  end

  test "oauth_scopes maps name fields to name scope" do
    program = Program.new(
      slug: 'test', name: 'T', form_url: 'https://forms.hackclub.com/x',
      owner_email: 'a@b.com', api_key: 'pk_unique1',
      scopes: { 'first_name' => true, 'last_name' => true }
    )
    scopes = program.oauth_scopes.split(' ')
    assert_includes scopes, 'name'
    # name should only appear once even though both first_name and last_name are enabled
    assert_equal 1, scopes.count('name')
  end

  test "oauth_scopes maps birthday to birthdate and addresses to address" do
    program = programs(:test_program)
    scopes = program.oauth_scopes.split(' ')
    assert_includes scopes, 'birthdate'
    assert_includes scopes, 'address'
  end

  test "oauth_scopes excludes disabled scopes" do
    program = Program.new(
      slug: 'minimal', name: 'M', form_url: 'https://forms.hackclub.com/x',
      owner_email: 'a@b.com', api_key: 'pk_unique2',
      scopes: { 'email' => true, 'birthday' => false }
    )
    scopes = program.oauth_scopes.split(' ')
    assert_includes scopes, 'email'
    refute_includes scopes, 'birthdate'
  end

  test "oauth_scopes handles blank scopes" do
    program = Program.new(
      slug: 'blank', name: 'B', form_url: 'https://forms.hackclub.com/x',
      owner_email: 'a@b.com', api_key: 'pk_unique3',
      scopes: {}
    )
    scopes = program.oauth_scopes.split(' ')
    assert_includes scopes, 'openid'
    assert_includes scopes, 'verification_status'
    assert_equal 2, scopes.length
  end
end
