require "test_helper"

class Users::EmailAddressesControllerTest < ActionDispatch::IntegrationTest
  include WebauthnTestHelper

  setup do
    @user = users(:nonstaff)
    sign_in_as @user
  end

  test "new" do
    get new_user_email_address_path(@user)
    assert_response :success
  end

  test "create changes the email in place and keeps the passkeys" do
    passkey = @user.identity.passkeys.create!(credential_id: "nonstaff-credential", public_key: webauthn_private_key.public_to_der)

    assert_no_difference -> { Identity.count } do
      post user_email_addresses_path(@user), params: { email_address: "renamed@example.com" }
    end

    assert_redirected_to user_path(@user)
    assert_equal "Email address updated", flash[:notice]
    assert_equal "renamed@example.com", @user.identity.reload.email_address
    assert_equal [ passkey ], @user.identity.passkeys.to_a
  end

  test "create refuses an email another identity uses" do
    post user_email_addresses_path(@user), params: { email_address: identities(:leo).email_address }

    assert_redirected_to new_user_email_address_path(@user)
    assert_equal "That email address is already in use", flash[:alert]
    assert_equal "nonstaff@example.com", @user.identity.reload.email_address
  end

  test "create refuses an invalid email" do
    post user_email_addresses_path(@user), params: { email_address: "not-an-email" }

    assert_redirected_to new_user_email_address_path(@user)
    assert_equal "Please enter a valid email address", flash[:alert]
  end
end
