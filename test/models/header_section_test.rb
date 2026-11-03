require "test_helper"

class HeaderSectionTest < ActiveSupport::TestCase
  test "a header section within 1 MB is not oversized, however long the body" do
    raw = "Subject: Hi\r\n\r\n" + ("x" * 76 + "\r\n") * 20_000

    assert_not HeaderSection.oversized?(raw)
  end

  test "a header section past 1 MB is oversized" do
    raw = "Subject: Hi\r\n" + ("X-Filler: #{"x" * 70}\r\n" * 16_000) + "\r\nBody.\r\n"

    assert HeaderSection.oversized?(raw)
  end

  test "a message past 1 MB with no empty line is all header section" do
    assert HeaderSection.oversized?("X-Filler: #{"x" * 70}\r\n" * 16_000)
  end
end
