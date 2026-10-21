require "test_helper"

class Relay::SealingKeyTest < ActiveSupport::TestCase
  setup do
    stub_env RELAY_HOSTNAME: "mx.example"
    publish_sealing_key
  end

  test "instance generates a key on first access and hands back the same one afterwards" do
    key = Relay::SealingKey.instance

    assert key.private_key.present?
    assert_equal DkimKey::SIZE, key.key.n.num_bits
    assert_equal key.id, Relay::SealingKey.instance.id
    assert_equal 1, Relay::SealingKey.count
  end

  test "the private key is encrypted at rest" do
    key = Relay::SealingKey.instance

    assert_not_equal key.private_key, key.ciphertext_for(:private_key)
  end

  test "publishes itself at arc._domainkey under the relay's mail domain" do
    record = with_env(RELAY_MAIL_DOMAIN: "mailer.example") { Relay::SealingKey.instance.dns_record }

    assert_equal "arc._domainkey.mailer.example", record.hostname
    assert_equal "TXT", record.type
    assert_match(/\Av=DKIM1; k=rsa; t=s; h=sha256; p=/, record.value)
  end

  test "seal adds one ARC set naming the mail domain and the concluded chain status" do
    sealed = with_env(RELAY_MAIL_DOMAIN: "mailer.example") do
      Relay::SealingKey.instance.seal("Subject: Hi\r\n\r\nBody",
        authentication_results: "mx.example; dmarc=pass", chain_status: "pass")
    end

    assert_match(/\AARC-Seal: /, sealed)
    assert_match(/cv=pass; d=mailer\.example;/, sealed)
    assert_match(/ARC-Message-Signature: .*s=arc;/m, sealed)
    assert_includes sealed, "ARC-Authentication-Results: i=1; mx.example; dmarc=pass\r\n"
  end

  test "seal refuses a chain status it would have to invent" do
    assert_raises ArgumentError do
      Relay::SealingKey.instance.seal("Subject: Hi\r\n\r\nBody",
        authentication_results: "mx.example; none", chain_status: "maybe")
    end
  end

  # A set whose key nobody can fetch fails the chain it joins, taking every earlier
  # hop's with it — so an unpublished key has to leave the message alone.
  test "seal leaves the message untouched until the key is published" do
    Relay::DnsCheck.instance.update!(sealing_key_status: :missing)
    raw = "Subject: Hi\r\n\r\nBody"

    with_env(RELAY_MAIL_DOMAIN: "mailer.example") do
      assert_equal raw, Relay::SealingKey.instance.seal(raw,
        authentication_results: "mx.example; dmarc=pass", chain_status: "pass")
    end
  end

  test "seal leaves the message untouched when there is no mail domain to seal under" do
    raw = "Subject: Hi\r\n\r\nBody"

    with_env(RELAY_MAIL_DOMAIN: "") do
      assert_equal raw, Relay::SealingKey.instance.seal(raw,
        authentication_results: "mx.example; dmarc=pass", chain_status: "pass")
    end
  end
end
