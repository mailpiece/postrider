require "test_helper"

class Adminland::DnsChecksControllerTest < ActionDispatch::IntegrationTest
  test "show has the records and their checks, under Adminland" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo
      dns_check = Relay::DnsCheck.instance
      dns_check.addresses.create!(address: "203.0.113.10", ptr_hostname: "mx.example", expected_ptr_hostname: "mx.example")
      dns_check.update!(address_status: :ok, ptr_status: :ok, spf_status: :ok, dns_checked_at: Time.current)

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".breadcrumbs a[href=?]", adminland_settings_path, text: "Adminland"
        assert_select ".breadcrumbs strong", text: "DNS records"
        assert_select "p", text: "DNS status: OK"
        assert_select ".dns-check__header", text: /Relay hostname\s+A\/AAAA\s+OK/
        assert_select ".dns-check .dns-record code", text: "203.0.113.10"
        assert_select ".dns-check__header", text: /Reverse DNS\s+PTR\s+OK/
        assert_select ".dns-check__header", text: /SPF\s+TXT\s+OK/
        assert_select ".dns-check__header", text: /ARC sealing key\s+TXT\s+Not checked/
        assert_select ".dns-check__header", text: /Certificate challenge\s+NS\s+Not checked/
        assert_select ".dns-check .dns-record code", text: "_acme-challenge.mx.example"
        assert_select ".dns-check__header", text: /Bounces\s+MX/
        assert_select "form[action=?]", adminland_dns_check_path, count: 1
      end
    end
  end

  test "show says a status shared by several records once, over the records it covers" do
    with_env(RELAY_HOSTNAME: "mx.example", RELAY_MAIL_DOMAIN: "mailer.example") do
      sign_in_as :leo
      dns_check = Relay::DnsCheck.instance
      dns_check.addresses.create!(address: "203.0.113.10", expected_ptr_hostname: "mx.example")
      dns_check.addresses.create!(address: "2001:db8::10", expected_ptr_hostname: "mx.example")
      dns_check.update!(ptr_status: :invalid, ptr_error: "PTR mismatch", mail_domain_status: :ok, dns_checked_at: Time.current)

      untenanted do
        get adminland_dns_check_path

        assert_select ".dns-check-group > .dns-check__header", text: /Mail domain and Bounces\s+A\/AAAA \+ MX\s+OK/
        assert_select ".dns-check-group > .dns-check__header", text: /Reverse DNS\s+PTR\s+Invalid/
        assert_select ".dns-check-group", text: /One check covers these 2 records\. PTR mismatch/
        assert_select ".dns-check-group .dns-check .status", count: 0
      end
    end
  end

  test "show includes the submission hostname's own record when it differs from the relay hostname" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: "smtp.example") do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".dns-check__header", text: /Submission hostname\s+A\/AAAA\s+Not checked/
        assert_select ".dns-check .dns-record code", text: "smtp.example"
        assert_select ".dns-check-group > .dns-check__header", text: /Certificate challenge\s+NS\s+Not checked/
        assert_select ".dns-check-group", text: /One check covers these 2 records/
        assert_select ".dns-check .dns-record code", text: "_acme-challenge.smtp.example"
      end
    end
  end

  test "show omits the submission hostname's record when it matches the relay hostname" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".dns-check .chip", text: "A/AAAA", count: 1
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
