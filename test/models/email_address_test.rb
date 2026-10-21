require "test_helper"

class EmailAddressTest < ActiveSupport::TestCase
  test "extract parses a display name address" do
    assert_equal "hello@lists.example.org", EmailAddress.extract("Lists <hello@lists.example.org>")
  end

  test "extract_list splits a comma-separated string into addresses" do
    assert_equal %w[ a@example.com b@example.com ], EmailAddress.extract_list("a@example.com, Bee <b@example.com>")
  end

  test "extract_list also splits comma-separated strings inside an array" do
    assert_equal %w[ a@example.com b@example.com c@example.com ],
      EmailAddress.extract_list([ "a@example.com, b@example.com", "c@example.com" ])
  end

  test "extract_list keeps a display name comma intact" do
    assert_equal [ "j@example.com" ], EmailAddress.extract_list('"Doe, Jane" <j@example.com>')
  end

  test "format_list splits a comma-separated string and preserves display names" do
    assert_equal [ "a@example.com", "Bee <b@example.com>" ],
      EmailAddress.format_list("a@example.com, Bee <b@example.com>")
  end
end
