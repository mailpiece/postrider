require "test_helper"

class Domain::AllowedIpsTest < ActiveSupport::TestCase
  test "the list drops blank lines, strips each address and collapses duplicates" do
    domains(:example).update!(allowed_ips: " 203.0.113.0/24 \r\n\r\n198.51.100.12\r\n203.0.113.0/24\r\n")

    assert_equal "203.0.113.0/24\n198.51.100.12", domains(:example).allowed_ips
  end

  test "an emptied list is stored as nothing at all" do
    domains(:example).update!(allowed_ips: " \r\n ")

    assert_nil domains(:example).allowed_ips
  end

  test "an empty list allows any address" do
    assert domains(:example).allows_ip?("198.51.100.12")
  end

  test "an address or a range lets its own in and keeps everyone else out" do
    domains(:example).update!(allowed_ips: "203.0.113.0/24\n198.51.100.12")

    assert domains(:example).allows_ip?("203.0.113.40")
    assert domains(:example).allows_ip?("::ffff:198.51.100.12")
    assert_not domains(:example).allows_ip?("198.51.100.13")
    assert_not domains(:example).allows_ip?("2001:db8::1")
    assert_not domains(:example).allows_ip?(nil)
  end

  test "only IPv4 addresses and ranges are accepted" do
    assert_not domains(:example).update(allowed_ips: "203.0.113.0/24\n2001:db8::1")

    assert_includes domains(:example).errors.full_messages, %(Allowed IPs can't hold "2001:db8::1": only IPv4 addresses and ranges)
  end

  test "the list has a ceiling" do
    addresses = (1..Domain::MAX_ALLOWED_IPS + 1).map { |number| "198.51.100.#{number}" }

    assert_not domains(:example).update(allowed_ips: addresses.join("\n"))

    assert_includes domains(:example).errors[:allowed_ips], "accepts at most #{Domain::MAX_ALLOWED_IPS} addresses or ranges"
  end

  test "changing the list is traced on the domain" do
    assert_difference -> { domains(:example).events.where(action: "domain_allowed_ips_changed").count }, 1 do
      domains(:example).update!(allowed_ips: "198.51.100.12")
    end
  end

  test "saving the list unchanged is not traced" do
    domains(:example).update!(allowed_ips: "198.51.100.12")

    assert_no_difference -> { domains(:example).events.where(action: "domain_allowed_ips_changed").count } do
      domains(:example).update!(allowed_ips: "198.51.100.12\r\n")
    end
  end
end
