require "test_helper"

class Domains::DnsChecksControllerTest < ActionDispatch::IntegrationTest
  test "checking DNS enqueues the check and redirects to the domain" do
    sign_in_as :leo
    domain = domains(:example)

    assert_enqueued_with job: DnsCheckJob, args: [ domain ] do
      post domain_dns_check_path(domain)
    end

    assert_redirected_to edit_domain_path(domain)
    assert_match "Checking DNS", flash[:notice]
  end

  test "a member cannot check a domain's DNS" do
    sign_in_as :nonstaff

    assert_no_enqueued_jobs only: DnsCheckJob do
      post domain_dns_check_path(domains(:example))
    end

    assert_response :forbidden
  end

  test "domains from other accounts can't be checked" do
    sign_in_as :leo

    assert_no_enqueued_jobs only: DnsCheckJob do
      post domain_dns_check_path(domains(:other_account))
    end

    assert_response :not_found
  end
end
