require "test_helper"

class My::OtherSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
    @current_session = Session.find_signed(parsed_cookies.signed[:session_token])
    @other_session = identities(:leo).sessions.create!
    @someone_elses_session = identities(:nonstaff).sessions.create!
  end

  test "destroy ends every other session and keeps this one" do
    confirm_sudo

    delete my_other_sessions_path

    assert_redirected_to user_path(users(:leo))
    assert_equal "Signed out of all other devices", flash[:notice]
    assert_not Session.exists?(@other_session.id)
    assert Session.exists?(@current_session.id)
    assert Session.exists?(@someone_elses_session.id)
  end

  test "destroy asks for a passkey first" do
    delete my_other_sessions_path

    assert_redirected_to new_my_sudo_path
    assert Session.exists?(@other_session.id)
  end
end
