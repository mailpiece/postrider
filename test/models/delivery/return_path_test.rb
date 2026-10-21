require "test_helper"

class Delivery::ReturnPathTest < ActiveSupport::TestCase
  setup do
    @domain = domains(:example).tap { it.update!(dmarc_status: :ok, return_path_status: :ok) }
    @delivery = deliveries(:queued)
  end

  test "address is a VERP bounces address on the mailer subdomain of the sending domain" do
    address = Delivery::ReturnPath.new(@delivery).address

    assert_equal Delivery::ReturnPath.verp.address_for(@delivery.id, domain: "mailer.example.com"), address
  end

  test "the address local-part stays within the RFC 5321 64-octet limit" do
    local = Delivery::ReturnPath.new(@delivery).address.split("@", 2).first

    assert_operator local.bytesize, :<, 64
    assert_match(/\Abounces\+#{@delivery.id}\.[0-9a-f]+\z/, local)
  end

  test "find_delivery round-trips the address back to its delivery" do
    address = Delivery::ReturnPath.new(@delivery).address

    assert_equal @delivery, Delivery::ReturnPath.find_delivery(address)
  end

  test "find_delivery rejects a tampered hmac" do
    tampered = tamper_hmac(Delivery::ReturnPath.new(@delivery).address)

    assert_nil Delivery::ReturnPath.find_delivery(tampered)
  end

  test "find_delivery rejects a structurally invalid address" do
    assert_nil Delivery::ReturnPath.find_delivery("recipient@example.com")
    assert_nil Delivery::ReturnPath.find_delivery("bounces+nohmac@mailer.example.com")
    assert_nil Delivery::ReturnPath.find_delivery(nil)
  end

  test "find_delivery does not resolve a delivery id under another account's domain" do
    domains(:other_account).update!(dmarc_status: :ok, return_path_status: :ok)
    other_delivery = deliver_from(domains(:other_account))

    forged = Delivery::ReturnPath.verp.address_for(other_delivery.id, domain: "mailer.#{@domain.name}")

    assert_nil Delivery::ReturnPath.find_delivery(forged)
  end

  test "find_delivery does not resolve an address minted for a different domain" do
    domains(:private).update!(dmarc_status: :ok, return_path_status: :ok)
    other_delivery = deliver_from(domains(:private))

    address = Delivery::ReturnPath.new(other_delivery).address
    resigned_for_another_domain = address.sub("@mailer.private.example", "@mailer.example.com")

    assert_nil Delivery::ReturnPath.find_delivery(resigned_for_another_domain)
  end

  test "address is nil when the domain has no custom Return-Path and no relay mail domain is configured" do
    with_env(RELAY_MAIL_DOMAIN: nil) do
      @domain.update!(return_path_status: nil)

      assert_nil Delivery::ReturnPath.new(@delivery).address
    end
  end

  test "address falls back to the relay-owned Return-Path when the domain has no custom one" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      delivery = basic_delivery

      assert_equal Delivery::ReturnPath.verp.address_for(delivery.id, domain: "relay.example"),
        Delivery::ReturnPath.new(delivery).address
    end
  end

  # Bounces from a forward are third-party traffic, so they answer to the relay
  # rather than to the tenant whose alias carried the message.
  test "a forward uses the relay Return-Path even where the domain has its own" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      forward = Message.create!(domain: @domain, mail_from: "jane@remote.example",
        raw: "Subject: Hi\r\n\r\nBody", origin: :forwarded)
      delivery = forward.deliveries.create!(rcpt_to: "recipient@example.com")

      assert @domain.return_path_enabled?
      assert_equal Delivery::ReturnPath.verp.address_for(delivery.id, domain: "relay.example"),
        Delivery::ReturnPath.new(delivery).address
    end
  end

  test "a relay-owned address round-trips through find_delivery and bounce_domain with no tenant in the address" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      delivery = basic_delivery
      address = Delivery::ReturnPath.new(delivery).address

      assert Delivery::ReturnPath.address?(address)
      assert_equal delivery, Delivery::ReturnPath.find_delivery(address)
      assert_equal delivery.domain, Delivery::ReturnPath.bounce_domain(address)
    end
  end

  test "a bounce to the relay's own mail matches no delivery, so the MX refuses it" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      message = Message.create!(domain: @domain, mail_from: "noreply@example.com", envelope_from: "",
        raw: "Subject: Hi\r\n\r\nBody", origin: :system)
      address = Delivery::ReturnPath.new(message.deliveries.create!(rcpt_to: "recipient@example.com")).address

      assert_equal "relay.example", address.split("@").last
      assert_nil Delivery::ReturnPath.find_delivery(address)
      assert_not Delivery::ReturnPath.address?(address)
    end
  end

  test "a tampered relay-owned token resolves to nothing" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      delivery = basic_delivery
      tampered = tamper_hmac(Delivery::ReturnPath.new(delivery).address)

      assert_nil Delivery::ReturnPath.find_delivery(tampered)
      assert_nil Delivery::ReturnPath.bounce_domain(tampered)
    end
  end

  test "address? accepts a valid relay bounce address for an existing delivery" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      delivery = basic_delivery

      assert Delivery::ReturnPath.address?(Delivery::ReturnPath.new(delivery).address)
    end
  end

  test "address? rejects a relay bounce address with a well-formed but invalid hmac" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      delivery = basic_delivery
      tampered = tamper_hmac(Delivery::ReturnPath.new(delivery).address)

      assert_not Delivery::ReturnPath.address?(tampered)
    end
  end

  test "address? rejects a relay bounce address whose delivery no longer exists" do
    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      delivery = basic_delivery
      address = Delivery::ReturnPath.new(delivery).address
      delivery.destroy!

      assert_not Delivery::ReturnPath.address?(address)
    end
  end

  test "domain_for and address? recognize a VERP address for an enabled domain" do
    address = Delivery::ReturnPath.new(@delivery).address

    assert_equal @domain, Delivery::ReturnPath.domain_for(address)
    assert Delivery::ReturnPath.address?(address)
  end

  test "address? rejects a VERP address once the account is cancelled" do
    address = Delivery::ReturnPath.new(@delivery).address
    @domain.account.create_cancellation!(initiated_by: users(:leo))

    assert_not Delivery::ReturnPath.address?(address)
  end

  test "domain_for is nil for a non-VERP address" do
    assert_nil Delivery::ReturnPath.domain_for("someone@example.com")
    assert_not Delivery::ReturnPath.address?("someone@example.com")
  end

  test "domain_for is nil once the domain is no longer return-path enabled" do
    address = Delivery::ReturnPath.new(@delivery).address
    @domain.update!(dmarc_status: nil)

    assert_nil Delivery::ReturnPath.domain_for(address)
    assert_not Delivery::ReturnPath.address?(address)
  end

  private
    # Verified so it may send at all, but without the advanced records — the one
    # configuration where ordinary mail still falls back to the relay's Return-Path.
    def basic_delivery
      deliver_from(domains(:private), status: nil)
    end

    def tamper_hmac(address)
      address.sub(/\.[0-9a-f]+@/, ".#{"0" * 16}@")
    end
end
