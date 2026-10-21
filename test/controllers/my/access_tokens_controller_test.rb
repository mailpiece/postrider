require "test_helper"

class My::AccessTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "index renders untenanted" do
    untenanted { get my_access_tokens_path }

    assert_response :success
    assert_select "a.breadcrumbs__home[href=?]", "/session/menu"
  end

  test "index renders in an account" do
    get my_access_tokens_path

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", user_path(users(:leo)), text: "Profile"
  end

  test "new asks for a passkey first" do
    get new_my_access_token_path
    assert_redirected_to new_my_sudo_path

    confirm_sudo
    get new_my_access_token_path
    assert_response :success
  end

  test "the passkey check lapses after thirty minutes" do
    confirm_sudo

    travel Session::SUDO_DURATION + 1.second do
      get new_my_access_token_path
    end

    assert_redirected_to new_my_sudo_path
  end
end
