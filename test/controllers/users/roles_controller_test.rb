require "test_helper"

class Users::RolesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "update changes the role and goes back to the people" do
    patch user_role_path(users(:nonstaff)), params: { user: { role: "admin" } }

    assert_redirected_to users_path
    assert users(:nonstaff).reload.admin?
  end
end
