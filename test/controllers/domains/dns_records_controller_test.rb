require "test_helper"

class Domains::DnsRecordsControllerTest < ActionDispatch::IntegrationTest
  test "shows the records that need work first, with what the domain can do" do
    sign_in_as :leo
    domain = domains(:unverified)
    domain.update!(mx_status: :ok, dkim_status: :missing, dmarc_status: :invalid, dns_checked_at: Time.current)

    get domain_dns_records_path(domain)

    assert_response :success
    assert_select ".dns-item__head", text: /Inbound\s+MX\s+OK/
    assert_select ".dns-item__head", text: /DKIM\s+TXT\s+Missing/
    assert_select ".dns-item__head", text: /DMARC\s+TXT\s+Invalid/
    assert_select ".dns-item__head", text: /Return-Path\s+CNAME\s+Not checked/
    assert_select ".dns-item__line input[readonly][aria-label=?]", "Name", count: 4
    assert_select ".settings-index__body p", text: /Receives mail\. Not verified for sending yet: the DKIM record is missing\./
    assert_equal %w[ DKIM DMARC Return-Path Inbound ], css_select(".dns-item__head strong").map(&:text)
  end

  test "a member cannot see the DNS records page" do
    sign_in_as :nonstaff

    get domain_dns_records_path(domains(:example))

    assert_response :forbidden
  end
end
