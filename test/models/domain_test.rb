require "test_helper"

class DomainTest < ActiveSupport::TestCase
  test "dmarc_record stays in monitoring mode and points aggregate reports at the domain's own inbox" do
    domain = domains(:example)

    value = domain.dmarc_record.value

    assert value.start_with?("v=DMARC1; p=none;"), value
    assert_includes value, "rua=mailto:dmarc-reports@#{domain.name}"
  end

  test "seeds postmaster and dmarc-reports mailboxes on create" do
    domain = Domain.create!(name: "domain-test.example", creator: users(:leo))

    assert domain.mailboxes.exists?(local_part: "postmaster")
    assert domain.mailboxes.exists?(local_part: "dmarc-reports")
  end

  test "accepts? is true for a registered domain and a registered mailbox" do
    assert Domain.accepts?("inbox@example.com")
  end

  test "accepts? is false for a registered domain and an unregistered local part" do
    assert_not Domain.accepts?("nobody@example.com")
  end

  test "accepts? is falsy for an unregistered domain" do
    assert_not Domain.accepts?("someone@unregistered-domain-test.example")
  end

  test "instance accepts? mirrors the class method for a specific address" do
    assert domains(:example).accepts?("inbox@example.com")
    assert_not domains(:example).accepts?("nobody@example.com")
  end

  test "catch_all_policy defaults to disabled" do
    assert Domain.new.disabled?
  end

  test "accepts? is false for an unregistered local part when catch_all_policy is disabled" do
    assert_not domains(:example).accepts?("nobody@example.com")
  end

  test "accepts? is true for an unregistered local part when catch_all_policy is discard" do
    domains(:example).update!(catch_all_policy: "discard")

    assert domains(:example).accepts?("nobody@example.com")
  end

  test "accepts? is true for an unregistered local part when catch_all_policy is forward" do
    domains(:example).update!(catch_all_policy: "forward")

    assert domains(:example).accepts?("nobody@example.com")
  end

  test "specifically_registered? ignores catch_all_policy and only matches real Mailbox/bounce-address entries" do
    domains(:example).update!(catch_all_policy: "forward")

    assert domains(:example).specifically_registered?("inbox@example.com")
    assert_not domains(:example).specifically_registered?("nobody@example.com")
  end

  test "specifically_registered? matches a Mailbox registered with its own literal +suffix" do
    domains(:example).mailboxes.create!(local_part: "somemailbox+test")

    assert domains(:example).specifically_registered?("somemailbox+test@example.com")
    assert_not domains(:example).specifically_registered?("somemailbox@example.com")
  end

  test "specifically_registered? still resolves a +suffix to its plain base Mailbox" do
    assert domains(:example).specifically_registered?("inbox+anything@example.com")
  end

  test "specifically_registered? treats dots as significant" do
    domains(:example).mailboxes.create!(local_part: "john.doe")

    assert domains(:example).specifically_registered?("john.doe@example.com")
    assert_not domains(:example).specifically_registered?("johndoe@example.com")
  end

  test "specifically_registered? strips a +suffix" do
    assert domains(:example).specifically_registered?("inbox+newsletter@example.com")
  end

  test "mailbox_for finds a +tag address's base mailbox" do
    assert_equal mailboxes(:inbox), domains(:example).mailbox_for("Inbox+news@example.com")
    assert_nil domains(:example).mailbox_for("nobody+news@example.com")
  end

  test "mailbox_for prefers a mailbox registered with its own +tag over the base" do
    tagged = domains(:example).mailboxes.create!(local_part: "inbox+news")

    assert_equal tagged, domains(:example).mailbox_for("inbox+news@example.com")
    assert_equal mailboxes(:inbox), domains(:example).mailbox_for("inbox+other@example.com")
  end

  test "verified? is false until dkim_status is OK" do
    assert_not domains(:unverified).verified?
  end

  test "verified? is true once dkim_status is OK" do
    assert domains(:example).verified?
  end

  test "verified scope returns only domains whose dkim_status is OK" do
    assert_includes Domain.verified, domains(:example)
    assert_not_includes Domain.verified, domains(:unverified)
  end

  test "dns_records lists inbound MX and DKIM, leaving the alternate CNAME off the basic list" do
    domain = domains(:example)

    types = domain.dns_records.map(&:type)

    assert_equal [ domain.mx_record, domain.dkim_record ], domain.dns_records
    assert_equal %w[ MX TXT ], types
  end

  test "return_path_record points at the mail domain, not the MX hostname" do
    with_env(RELAY_HOSTNAME: "mx.relay.example", RELAY_MAIL_DOMAIN: "mailer.relay.example") do
      record = domains(:example).return_path_record

      assert_equal "mailer.example.com", record.hostname
      assert_equal "CNAME", record.type
      assert_equal "mailer.relay.example.", record.value
    end
  end

  test "return_path_record falls back to the MX hostname when no mail domain is set" do
    with_env(RELAY_HOSTNAME: "mx.relay.example", RELAY_MAIL_DOMAIN: nil) do
      assert_equal "mx.relay.example.", domains(:example).return_path_record.value
    end
  end

  test "name_for extracts the downcased domain of an address" do
    assert_equal "example.com", Domain.name_for("Someone <PERSON@Example.COM>")
    assert_equal "example.com", Domain.name_for("plain@example.com")
    assert_nil Domain.name_for("")
  end

  test "removing a domain takes its configuration at once and its mail later" do
    domain = domains(:example)
    delivery = create_delivery

    assert_enqueued_jobs 2, only: Domain::PurgeMailJob do
      domain.destroy!
    end

    assert_empty Mailbox.where(domain_id: domain.id)
    assert_empty SendingToken.where(domain_id: domain.id)
    assert_empty Webhook.where(domain_id: domain.id)
    assert_empty Contact.where(domain_id: domain.id)
    assert_empty Access.where(domain_id: domain.id)
    assert Delivery.exists?(delivery.id)
    assert_enqueued_with job: Domain::PurgeMailJob, args: [ domain.id ], at: 10.minutes.from_now
  end

  test "mail of a removed domain is out of every user's sight" do
    domain = domains(:example)
    create_delivery
    create_inbound_email.track_event "received"
    user = users(:leo)

    domain.destroy!

    assert Mailpiece.where(domain_id: domain.id).exists?
    assert_empty user.accessible_mailpieces.where(domain_id: domain.id)
    assert_empty user.accessible_events.where(domain_id: domain.id)
    assert_empty user.accessible_contacts.where(domain_id: domain.id)
    assert_empty domain.account.mailpieces.where(domain_id: domain.id)
  end
end
