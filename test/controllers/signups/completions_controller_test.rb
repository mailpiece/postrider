require "test_helper"

class Signups::CompletionsControllerTest < ActionDispatch::IntegrationTest
  include WebauthnTestHelper

  setup do
    untenanted do
      post signup_path, params: { signup: { email_address: "newcomer@example.com" } }
      post session_passkey_registration_path, params: build_attestation_params(challenge: request_webauthn_challenge(purpose: "registration"))
    end
  end

  test "new" do
    untenanted { get new_signup_completion_path }

    assert_response :success
  end

  test "create" do
    assert_difference -> { Account.count }, +1 do
      untenanted { post signup_completion_path, params: { signup: { full_name: "New Comer" } } }
    end

    assert_response :redirect
    assert newcomer.users.sole.owner?
  end

  test "create is refused once the one account exists" do
    with_multi_tenant_mode(false) do
      untenanted do
        assert_no_difference -> { Account.count } do
          post signup_completion_path, params: { signup: { full_name: "New Comer" } }
        end

        assert_redirected_to new_session_url
      end
    end
  end

  test "create makes the first account on an empty install" do
    Account.stubs(:none?).returns(true)

    with_multi_tenant_mode(false) do
      assert_difference -> { Account.count }, +1 do
        untenanted { post signup_completion_path, params: { signup: { full_name: "New Comer" } } }
      end
    end

    assert_response :redirect
    assert newcomer.users.sole.owner?
  end

  private
    def newcomer
      Identity.find_by!(email_address: "newcomer@example.com")
    end
end
