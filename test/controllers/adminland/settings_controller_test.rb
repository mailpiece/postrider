require "test_helper"

class Adminland::SettingsControllerTest < ActionDispatch::IntegrationTest
  test "staff can open Adminland" do
    sign_in_as :leo

    untenanted do
      get adminland_settings_path

      assert_response :success
    end
  end

  test "non-staff are forbidden" do
    sign_in_as :nonstaff

    untenanted do
      get adminland_settings_path

      assert_response :forbidden
    end
  end

  test "signed out visitors are sent to sign in" do
    untenanted do
      get adminland_settings_path

      assert_redirected_to new_session_path
    end
  end
end
