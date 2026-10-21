require "test_helper"

class JoinCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:davids_account)
    @join_code = account_join_codes(:davids_account)
  end

  test "new" do
    get join_path(code: @join_code.code, script_name: @account.slug)

    assert_response :success
    assert_includes response.body, "Join Leo"
  end

  test "new with an invalid code" do
    get join_path(code: "INVALID-CODE", script_name: @account.slug)

    assert_response :not_found
  end

  test "new with an inactive code" do
    @join_code.update!(usage_count: @join_code.usage_limit)

    get join_path(code: @join_code.code, script_name: @account.slug)

    assert_response :gone
    assert_includes response.body, "This invitation link can no longer be used"
  end

  test "create waits for the passkey before adding the person" do
    assert_difference -> { Identity.count }, 1 do
      assert_no_difference -> { User.count } do
        post join_path(code: @join_code.code, script_name: @account.slug), params: { email_address: "new_user@example.com" }
      end
    end

    assert_redirected_to new_session_passkey_registration_url(script_name: nil)
    assert_equal new_users_verification_url(script_name: @account.slug), session[:return_to_after_authenticating]
  end

  test "create for an existing member redirects to the account" do
    identity = identities(:leo)
    sign_in_as :leo

    assert identity.users.exists?(account: @account), "Leo should be a member for this test"

    assert_no_difference -> { Identity.count } do
      assert_no_difference -> { User.count } do
        post join_path(code: @join_code.code, script_name: @account.slug), params: { email_address: identity.email_address }
      end
    end

    assert_redirected_to landing_url(script_name: @account.slug)
  end

  test "create for a different identity terminates the existing session" do
    sign_in_as :leo

    assert_difference -> { Identity.count }, 1 do
      assert_no_difference -> { User.count } do
        post join_path(code: @join_code.code, script_name: @account.slug), params: { email_address: "new_user@example.com" }
      end
    end

    assert_redirected_to new_session_passkey_registration_url(script_name: nil)
    assert_not_predicate cookies[:session_token], :present?
  end

  test "create with an email that already has an account goes to sign in" do
    assert_no_difference -> { User.count } do
      post join_path(code: @join_code.code, script_name: @account.slug), params: { email_address: identities(:other).email_address }
    end

    assert_redirected_to new_session_url(script_name: nil)
    assert_nil flash[:alert]
    assert_nil cookies[:pending_passkey_registration_token]
  end

  test "create retries an abandoned join with the same empty identity" do
    identity = Identity.create!(email_address: "abandoned@example.com")

    assert_no_difference -> { Identity.count } do
      post join_path(code: @join_code.code, script_name: @account.slug), params: { email_address: identity.email_address }
    end

    assert_redirected_to new_session_passkey_registration_url(script_name: nil)
  end

  test "create with an invalid email address" do
    assert_no_difference -> { Identity.count } do
      assert_no_difference -> { User.count } do
        post join_path(code: @join_code.code, script_name: @account.slug), params: { email_address: "not-a-valid-email" }
      end
    end

    assert_response :unprocessable_entity
  end

  test "create is rate limited" do
    Rails.cache.stubs(:increment).returns(11)

    post join_path(code: @join_code.code, script_name: @account.slug), params: { email_address: "test@example.com" }

    assert_response :too_many_requests
  end
end
