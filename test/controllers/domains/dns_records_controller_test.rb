require "test_helper"

class Domains::DnsRecordsControllerTest < ActionDispatch::IntegrationTest
  test "an admin sees the DNS records" do
    sign_in_as :leo
    domain = domains(:unverified)
    domain.update!(mx_status: :ok, dkim_status: :missing, dmarc_status: :invalid, dns_checked_at: Time.current)

    get domain_dns_records_path(domain)

    assert_response :success
  end

  test "a member cannot see the DNS records page" do
    sign_in_as :nonstaff

    get domain_dns_records_path(domains(:example))

    assert_response :forbidden
  end

  test "the records come as JSON in publishing order with what the last check found" do
    stub_env RELAY_HOSTNAME: "relay.example"
    sign_in_as :leo
    domain = domains(:example)
    domain.update!(mx_status: :ok, dkim_status: :missing, dkim_error: "No DKIM record exists at postrider._domainkey.example.com", dns_checked_at: Time.current)

    get domain_dns_records_path(domain), as: :json

    assert_response :success
    assert_equal "example.com", response.parsed_body["name"]
    assert_equal false, response.parsed_body["verified"]
    assert_equal domain.dns_checked_at.utc.iso8601(3), response.parsed_body["checked_at"]

    records = response.parsed_body["records"]
    assert_equal %w[ Inbound DKIM DMARC Return-Path ], records.map { |record| record["title"] }
    assert_equal [ "ok", "missing", nil, nil ], records.map { |record| record["status"] }
    assert_equal({ "title" => "DKIM", "type" => "TXT", "name" => "postrider._domainkey.example.com", "value" => domain.dkim_record.value,
                   "status" => "missing", "error" => "No DKIM record exists at postrider._domainkey.example.com" }, records.second)
  end

  test "a member cannot read the records as JSON" do
    sign_in_as :nonstaff

    get domain_dns_records_path(domains(:example)), as: :json

    assert_response :forbidden
  end
end
