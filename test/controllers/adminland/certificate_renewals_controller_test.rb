require "test_helper"

class Adminland::CertificateRenewalsControllerTest < ActionDispatch::IntegrationTest
  test "create enqueues a renewal" do
    sign_in_as :leo

    untenanted do
      assert_enqueued_with job: Relay::Certificate::RenewalJob do
        post adminland_certificate_renewal_path
      end

      assert_redirected_to adminland_certificate_path
    end
  end

  test "non-staff are forbidden" do
    sign_in_as :nonstaff

    untenanted do
      post adminland_certificate_renewal_path
      assert_response :forbidden
    end
  end
end
