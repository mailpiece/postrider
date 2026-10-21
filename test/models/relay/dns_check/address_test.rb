require "test_helper"

class Relay::DnsCheck::AddressTest < ActiveSupport::TestCase
  test "ptr_matches_expected_hostname? compares the observed PTR to this row's expectation" do
    address = Relay::DnsCheck::Address.new(address: "203.0.113.10", ptr_hostname: "mx.example", expected_ptr_hostname: "mx.example")
    assert address.ptr_matches_expected_hostname?

    address.ptr_hostname = "other.example"
    assert_not address.ptr_matches_expected_hostname?

    address.ptr_hostname = nil
    assert_not address.ptr_matches_expected_hostname?
  end
end
