require "test_helper"

class Adminland::DnsChecksControllerTest < ActionDispatch::IntegrationTest
  test "show has the records that need work first, under Adminland" do
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
        assert_select ".settings-index__body .status--badge", text: "OK"
        assert_select ".dns-list.dns-list--attention"
        assert_select ".dns-item__head", text: /Relay hostname\s+A\/AAAA\s+OK/
        assert_select ".dns-item__line input[value=?]", "203.0.113.10"
        assert_select ".dns-item__head", text: /Reverse DNS\s+PTR\s+OK/
        assert_select ".dns-item__head", text: /SPF\s+TXT\s+OK/
        assert_select ".dns-item__head", text: /ARC sealing key\s+TXT\s+Not checked/
        assert_select ".dns-item__head", text: /Certificate challenge\s+NS\s+Not checked/
        assert_select ".dns-item__line input[value=?]", "_acme-challenge.mx.example"
        assert_select ".dns-item__head", text: /\A\s*Bounces\s+MX\s*\z/
        assert_select "form[action=?]", adminland_dns_check_path, count: 1
        assert_equal [ "ARC sealing key", "Certificate challenge", "Relay hostname", "Bounces", "Reverse DNS", "SPF" ],
          css_select(".dns-item__head strong").map(&:text)
      end
    end
  end

  test "show gives each record the status of the check that covers it" do
    with_env(RELAY_HOSTNAME: "mx.example", RELAY_MAIL_DOMAIN: "mailer.example") do
      sign_in_as :leo
      dns_check = Relay::DnsCheck.instance
      dns_check.addresses.create!(address: "203.0.113.10", expected_ptr_hostname: "mx.example")
      dns_check.addresses.create!(address: "2001:db8::10", expected_ptr_hostname: "mx.example")
      dns_check.update!(ptr_status: :invalid, ptr_error: "PTR mismatch", mail_domain_status: :ok, dns_checked_at: Time.current)

      untenanted do
        get adminland_dns_check_path

        assert_select ".settings-index__body .status--badge", text: "Not ready"
        assert_select ".dns-item.dns-item--found .dns-item__head", text: /Mail domain\s+A\/AAAA\s+OK/
        assert_select ".dns-item.dns-item--found .dns-item__head", text: /Bounces\s+MX\s+OK/
        assert_select ".dns-item:not(.dns-item--found) .dns-item__head", text: /Reverse DNS\s+PTR\s+Invalid/, count: 2
        assert_select ".dns-item__error", text: "PTR mismatch", count: 2
      end
    end
  end

  test "show includes the submission hostname's own record when it differs from the relay hostname" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: "smtp.example") do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".dns-item__head", text: /Submission hostname\s+A\/AAAA\s+Not checked/
        assert_select ".dns-item__line input[value=?]", "smtp.example"
        assert_select ".dns-item__head", text: /Certificate challenge\s+NS\s+Not checked/, count: 2
        assert_select ".dns-item__line input[value=?]", "_acme-challenge.smtp.example"
      end
    end
  end

  test "show omits the submission hostname's record when it matches the relay hostname" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".dns-item .chip", text: "A/AAAA", count: 1
      end
    end
  end

  test "show says what to set when the relay hostname isn't configured, with nothing to check" do
    with_env(RELAY_HOSTNAME: nil, BASE_URL: nil) do
      sign_in_as :leo

      untenanted do
        get adminland_dns_check_path

        assert_response :success
        assert_select ".settings-index__body p", text: /Not configured\. Set ENV RELAY_HOSTNAME/
        assert_select ".dns-item", count: 0
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
