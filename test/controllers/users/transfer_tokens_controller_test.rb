require "test_helper"

class Users::TransferTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "create issues a teammate a sign-in link in the admin's name" do
    confirm_sudo

    assert_difference -> { identities(:nonstaff).transfers.count }, 1 do
      post user_transfer_token_path(users(:nonstaff))
    end

    assert_redirected_to user_path(users(:nonstaff))
    assert_equal users(:leo), identities(:nonstaff).transfer.issuer
  end

  test "create asks the admin to confirm first" do
    assert_no_difference -> { identities(:nonstaff).transfers.count } do
      post user_transfer_token_path(users(:nonstaff))
    end

    assert_redirected_to new_my_sudo_path
  end

  test "create is forbidden to a member" do
    logout_and_sign_in_as :nonstaff
    confirm_sudo

    assert_no_difference -> { identities(:leo).transfers.count } do
      post user_transfer_token_path(users(:leo))
    end

    assert_response :forbidden
  end

  test "create is forbidden for a teammate who belongs to another account too" do
    confirm_sudo
    identities(:nonstaff).join(accounts(:other_account))

    assert_no_difference -> { identities(:nonstaff).transfers.count } do
      post user_transfer_token_path(users(:nonstaff))
    end

    assert_response :forbidden
  end

  test "create is not found for another account's user" do
    confirm_sudo

    post user_transfer_token_path(users(:other))

    assert_response :not_found
  end
end
