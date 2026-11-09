require "test_helper"

class Adminland::DnsChecksControllerTest < ActionDispatch::IntegrationTest
  test "show offers a DNS check once the relay hostname is set" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select "form[action=?]", adminland_dns_check_path
      end
    end
  end

  test "show includes the submission hostname's own record when it differs from the relay hostname" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: "smtp.example") do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".dns-item__head", text: /Submission hostname/
      end
    end
  end

  test "show omits the submission hostname's record when it matches the relay hostname" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".dns-item__head", text: /Submission hostname/, count: 0
      end
    end
  end

  test "show offers no check while the relay hostname isn't configured" do
    with_env(RELAY_HOSTNAME: nil, BASE_URL: nil) do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select "form[action=?]", adminland_dns_check_path, count: 0
      end
    end
  end

  test "checking DNS enqueues the check and comes back to the records" do
    sign_in_as :leo

    untenanted do
      assert_enqueued_with job: DnsCheckJob, args: [ Relay::DnsCheck.instance ] do
        post adminland_dns_check_path
      end

      assert_redirected_to adminland_dns_check_path
      assert_match "Checking DNS", flash[:notice]
    end
  end

  test "non-staff are refused" do
    sign_in_as :nonstaff

    untenanted do
      get adminland_dns_check_path
      assert_response :forbidden

      assert_no_enqueued_jobs only: DnsCheckJob do
        post adminland_dns_check_path
      end
      assert_response :forbidden
    end
  end
end
