require "test_helper"

class Delivery::DkimSigningTest < ActiveSupport::TestCase
  include DkimTestHelper

  test "signs with the given domain's selector and key" do
    raw = "From: me@example.com\r\nTo: you@example.com\r\nSubject: Hi\r\n\r\nBody"

    signed = Delivery::DkimSigning.sign(raw, domain: domains(:example))

    assert_match(/\ADKIM-Signature:/, signed)
    assert_match(/d=example\.com;/, signed)
    assert_match(/s=#{domains(:example).dkim_selector};/, signed)
    assert verify_dkim(signed, domains(:example).dkim_key.public_key)
  end

  # Signs with the message's domain even when From: is unparseable.
  test "signs regardless of what the From: header says" do
    raw = "From: me@somewhere-else.example\r\nSubject: Hi\r\n\r\nBody"

    signed = Delivery::DkimSigning.sign(raw, domain: domains(:example))

    assert_match(/d=example\.com;/, signed)
    assert verify_dkim(signed, domains(:example).dkim_key.public_key)
  end
end
