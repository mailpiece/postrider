require "test_helper"

class Event::DescriptionTest < ActiveSupport::TestCase
  test "outbound events name the recipient" do
    assert_equal "Delivered mail to a@example.com", describe("delivery_delivered", rcpt_to: "a@example.com")
    assert_equal "Bounced mail to a@example.com", describe("delivery_bounced", rcpt_to: "a@example.com")
  end

  test "a failed delivery says whether we skipped it or gave up on it" do
    assert_equal "Skipped suppressed recipient a@example.com",
      describe("delivery_failed", rcpt_to: "a@example.com", reason: "suppressed")
    assert_equal "Gave up delivering to a@example.com",
      describe("delivery_failed", rcpt_to: "a@example.com", reason: "exhausted")
  end

  test "routine traffic still reads as a sentence on the record it belongs to" do
    assert_equal "Deferred mail to a@example.com, will retry",
      describe("delivery_deferred", rcpt_to: "a@example.com", smtp_code: "451")
    assert_equal "Received inbound mail for list@example.com",
      describe("inbound_email_received", rcpt_to: "list@example.com")
    assert_equal "Received a bounce for bounces@example.com",
      describe("inbound_email_bounce_received", rcpt_to: "bounces@example.com")
  end

  test "inbound events distinguish a discarded bounce from discarded mail" do
    assert_equal "Never forwarded inbound mail to list@example.com",
      describe("inbound_email_failed", rcpt_to: "list@example.com", reason: "abandoned")
    assert_equal "Discarded inbound mail to junk@example.com",
      describe("inbound_email_discarded", rcpt_to: "junk@example.com", reason: "unregistered_recipient")
    assert_equal "Discarded a bounce for an unknown delivery",
      describe("inbound_email_discarded", rcpt_to: "bounces@example.com", reason: "uncorrelated_bounce")
  end

  test "a forwarded event names both the mailbox and where the mail went on to" do
    assert_equal "Forwarded inbound mail for list@example.com on to elsewhere@other.example",
      describe("inbound_email_forwarded", rcpt_to: "list@example.com", forward_to: "elsewhere@other.example")
  end

  test "a hold says why, since the reason is the whole reason to look" do
    assert_equal "Held inbound mail for list@example.com because nothing vouches for its From address",
      describe("inbound_email_held", rcpt_to: "list@example.com", reason: "unauthenticated_sender")
    assert_equal "Held inbound mail for list@example.com because its sender was not approved",
      describe("inbound_email_held", rcpt_to: "list@example.com", reason: "denied_sender")
  end

  test "a hold for an unrecognised reason still reads as a sentence" do
    assert_equal "Held inbound mail for list@example.com",
      describe("inbound_email_held", rcpt_to: "list@example.com", reason: "something_new")
  end

  test "a deactivated webhook counts its failures" do
    assert_equal "Deactivated webhook after 10 failed deliveries",
      describe("webhook_deactivated", consecutive_failures_count: 10, code: 500)
  end

  test "domain events name the domain" do
    domain = domains(:example)

    assert_equal "DNS verified for example.com", describe("domain_verified", eventable: domain)
    assert_equal "DNS verification lost for example.com: No DKIM record exists",
      describe("domain_verification_lost", eventable: domain, status: "missing", error: "No DKIM record exists")
  end

  test "a withheld delivery names its phrase to an admin only" do
    event = Event.new(action: "delivery_withheld", particulars: { "rcpt_to" => "a@example.com", "phrase" => "free money" })

    assert_equal %(Withheld mail to a@example.com because it contains the blocked phrase "free money"), event.description_for(users(:leo))
    assert_equal "Withheld mail to a@example.com", event.description_for(users(:nonstaff))
    assert_equal "Withheld mail to a@example.com", event.description
  end

  test "a change to the blocked phrases says so and no more" do
    assert_equal "Blocked phrases changed", describe("domain_blocked_phrases_changed")
  end

  test "a change to the allowed IPs says so and no more" do
    assert_equal "Allowed IPs changed", describe("domain_allowed_ips_changed")
  end

  test "turning receiving or sending off names the domain" do
    assert_equal "Receiving turned off for example.com", describe("domain_receiving_turned_off", eventable: domains(:example))
    assert_equal "Sending turned off for example.com", describe("domain_sending_turned_off", eventable: domains(:example))
  end

  test "turning bulk mail on or off names the domain" do
    assert_equal "Bulk mail turned on for example.com", describe("domain_bulk_turned_on", eventable: domains(:example))
    assert_equal "Bulk mail turned off for example.com", describe("domain_bulk_turned_off", eventable: domains(:example))
  end

  test "a paused recipient domain is named" do
    assert_equal "Paused sending to gmail.com because its mail servers refuse this server's IP",
      describe("recipient_domain_paused", recipient_domain: "gmail.com")
  end

  test "a paused provider is named with the domain that tripped it" do
    assert_equal "Paused sending to Outlook.com (hotmail.com) because its mail servers refuse this server's IP",
      describe("recipient_domain_paused", recipient_domain: "hotmail.com", provider: "outlook")
    assert_equal "Resumed sending to Outlook.com (hotmail.com)", describe("recipient_domain_resumed", recipient_domain: "hotmail.com", provider: "outlook")
  end

  test "a resumed recipient domain is named" do
    assert_equal "Resumed sending to gmail.com", describe("recipient_domain_resumed", recipient_domain: "gmail.com")
  end

  test "mail held by a paused domain says so" do
    assert_equal "Deferred mail to a@gmail.com while sending to its domain is paused, will retry",
      describe("delivery_deferred", rcpt_to: "a@gmail.com", reason: "recipient_domain_paused")
  end

  test "sending token events name the token" do
    assert_equal "Created sending token Production", describe("sending_token_created", token_name: "Production")
    assert_equal "Revoked sending token Production", describe("sending_token_revoked", token_name: "Production")
    assert_equal "Refused sending token Production from 181.110.44.220, not in Allowed IPs",
      describe("sending_token_refused", token_name: "Production", ip: "181.110.44.220")
  end

  test "an unrecognised action falls back to its humanized name" do
    assert_equal "Delivery thing", describe("delivery_thing")
  end

  private
    def describe(action, eventable: nil, **particulars)
      Event.new(action: action, eventable: eventable, particulars: particulars.stringify_keys).description
    end
end
