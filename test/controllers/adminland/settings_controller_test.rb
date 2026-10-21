require "test_helper"

class Adminland::SettingsControllerTest < ActionDispatch::IntegrationTest
  test "show lists a row for each screen, with how it stands" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo

      untenanted do
        get adminland_settings_path

        assert_response :success
        assert_select "ul.rows li.row", count: 4
        assert_select "li.row a[href=?]", adminland_dns_check_path, text: /DNS records\s+Not ready/
        assert_select "li.row a[href=?]", adminland_certificate_path, text: /TLS certificate\s+No certificate yet/
        assert_select "li.row a[href=?]", adminland_mission_control_jobs_path, text: /Jobs/
        assert_select "li.row a[href=?]", adminland_pauses_path, text: /Paused domains\s+None/
        assert_select "li.row .icon", count: 4
        assert_select "form[method=post]", count: 0
        assert_select ".breadcrumbs a[href=?]", session_menu_path
      end
    end
  end

  test "show says the DNS is OK once every check passes" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo
      Relay::DnsCheck.instance.update!(address_status: :ok, ptr_status: :ok, spf_status: :ok)

      untenanted do
        get adminland_settings_path

        assert_select "li.row a[href=?]", adminland_dns_check_path, text: /DNS records\s+OK/
      end
    end
  end

  test "show says the hostname is not configured" do
    with_env(RELAY_HOSTNAME: nil) do
      sign_in_as :leo

      untenanted do
        get adminland_settings_path

        assert_select "li.row a[href=?]", adminland_dns_check_path, text: /DNS records\s+Not configured/
      end
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
