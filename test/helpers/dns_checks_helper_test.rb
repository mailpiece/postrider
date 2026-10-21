require "test_helper"

class DnsChecksHelperTest < ActionView::TestCase
  test "labels known statuses" do
    assert_equal "OK", dns_status_label("ok")
    assert_equal "Missing", dns_status_label("missing")
    assert_equal "Invalid", dns_status_label("invalid")
  end

  test "humanizes an unknown status" do
    assert_equal "Pending recheck", dns_status_label("pending_recheck")
  end

  test "reports a nil status as not checked" do
    assert_equal "Not checked", dns_status_label(nil)
  end
end
