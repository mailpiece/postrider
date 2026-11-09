require "test_helper"

class Adminland::CertificatesControllerTest < ActionDispatch::IntegrationTest
  test "show has the certificate's state and the NS record delegating its challenge name to the relay" do
    with_env(RELAY_HOSTNAME: "mx.example") do
      sign_in_as :leo

      untenanted do
        get adminland_certificate_path

        assert_response :success
        assert_select "p", text: /No certificate installed/
        assert_select "code", text: "_acme-challenge.mx.example"
      end
    end
  end

  test "show names every challenge name the certificate covers" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: "smtp.example") do
      Relay::DnsCheck.instance.update!(acme_delegation_status: :missing, acme_delegation_error: "No NS record yet for _acme-challenge.smtp.example")
      sign_in_as :leo

      untenanted do
        get adminland_certificate_path

        assert_select "code", text: "_acme-challenge.mx.example"
        assert_select "code", text: "_acme-challenge.smtp.example"
      end
    end
  end

  test "show asks for the hostname before any record while none is configured" do
    with_env(RELAY_HOSTNAME: nil, BASE_URL: nil) do
      sign_in_as :leo

      untenanted do
        get adminland_certificate_path

        assert_response :success
        assert_select "p", text: /Set ENV RELAY_HOSTNAME, or BASE_URL/
      end
    end
  end

  test "show renders the last renewal error" do
    Relay::Certificate.instance.update!(renewal_error: "Acme::Client::Error: rate limited")
    sign_in_as :leo

    untenanted do
      get adminland_certificate_path

      assert_response :success
      assert_match "rate limited", response.body
    end
  end

  test "non-staff are forbidden" do
    sign_in_as :nonstaff

    untenanted do
      get adminland_certificate_path

      assert_response :forbidden
    end
  end
end
