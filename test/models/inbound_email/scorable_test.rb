require "test_helper"

class InboundEmail::ScorableTest < ActiveSupport::TestCase
  test "forwarding scores the mail within a few seconds, before it records the receipt" do
    stub_env MAILSCORE_URL: "http://mailscore.test:8080"
    email = create_inbound_email
    MailScore::Client.expects(:new).with(read_timeout: 4, deadline: 5).returns(stub(check: verdict(score: 1.5)))

    assert_no_enqueued_jobs only: InboundEmail::ScoreJob do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.delivered?
    assert_equal %w[ inbound_email_scored inbound_email_received ], email.events.order(:id).pluck(:action)
  end

  test "new mail is not queued for scoring until it is forwarded" do
    stub_env MAILSCORE_URL: "http://mailscore.test:8080"

    assert_no_enqueued_jobs only: InboundEmail::ScoreJob do
      create_inbound_email
    end
  end

  test "a scorer that is unreachable or too slow leaves the mail to forward unscored and to score later" do
    stub_env MAILSCORE_URL: "http://mailscore.test:8080"
    email = create_inbound_email
    MailScore::Client.any_instance.expects(:check).raises(MailScore::Client::Unreachable, "no answer within 5 seconds")

    assert_enqueued_with job: InboundEmail::ScoreJob, args: [ email ] do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.delivered?
    assert_not email.scored?
  end

  test "a scorer that refuses the mail leaves it to forward unscored and to score later" do
    stub_env MAILSCORE_URL: "http://mailscore.test:8080"
    email = create_inbound_email
    MailScore::Client.any_instance.expects(:check).raises(MailScore::Client::Error.new("unavailable", status: 503))

    assert_enqueued_with job: InboundEmail::ScoreJob, args: [ email ] do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.delivered?
  end

  test "discarded mail, never forwarded, is queued for scoring" do
    stub_env MAILSCORE_URL: "http://mailscore.test:8080"
    email = create_inbound_email(rcpt_to: "randomjunk@example.com")

    assert_enqueued_with job: InboundEmail::ScoreJob, args: [ email ] do
      email.discard
    end
  end

  test "a bounce correlated to its delivery is queued for scoring once" do
    stub_env MAILSCORE_URL: "http://mailscore.test:8080"
    email = create_inbound_email(mail_from: "")
    Delivery::ReturnPath.stubs(:find_delivery).returns(stub(record_async_bounce: true))

    assert_enqueued_jobs 1, only: InboundEmail::ScoreJob do
      email.correlate_bounce
    end
  end

  test "a bounce that correlates to nothing is queued for scoring once, as a discard" do
    stub_env MAILSCORE_URL: "http://mailscore.test:8080"
    email = create_inbound_email(mail_from: "")
    Delivery::ReturnPath.stubs(:find_delivery).returns(nil)

    assert_enqueued_jobs 1, only: InboundEmail::ScoreJob do
      email.correlate_bounce
    end
  end

  test "nothing is queued for mail never forwarded without MAILSCORE_URL" do
    stub_env MAILSCORE_URL: nil

    assert_no_enqueued_jobs only: InboundEmail::ScoreJob do
      create_inbound_email(rcpt_to: "randomjunk@example.com").discard
    end
  end

  test "nothing is scored, queued or recorded without MAILSCORE_URL" do
    stub_env MAILSCORE_URL: nil
    MailScore::Client.any_instance.expects(:check).never

    email = create_inbound_email
    assert_no_enqueued_jobs only: InboundEmail::ScoreJob do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.delivered?
    assert_not email.scored?
  end

  test "score_now sends the message with its envelope and records the verdict as an event" do
    email = create_inbound_email(mail_from: "a@sender.example", rcpt_to: "b@example.com",
      remote_ip: "203.0.113.9", helo: "mx.sender.example", remote_host: "mx.sender.example")

    MailScore::Client.any_instance.expects(:check)
      .with(SIMPLE_RAW, ip: "203.0.113.9", helo: "mx.sender.example", hostname: "mx.sender.example",
        from: "a@sender.example", rcpt: "b@example.com", queue_id: email.id)
      .returns(verdict(action: :add_header, score: 6.5, symbols: [
        symbol("HOSTNAME_UNKNOWN", 2.5, "203.0.113.9", "Sending server has no verified host name"),
        symbol("REVERSE_DNS_NONE", 2.0, nil, "No reverse DNS for the sending server"),
        symbol("ATTACHMENT_RISKY_EXTENSION", 2.0, "#{"x" * 120}.exe", "Risky attachment type"),
        symbol("CLIENT_LISTED", 1.0, nil, nil) ]))

    email.score_now

    event = email.events.sole
    assert_equal "inbound_email_scored", event.action
    assert_equal({ "action" => "add_header", "score" => 6.5, "complete" => true,
      "symbols" => [ [ "HOSTNAME_UNKNOWN", 2.5, "Sending server has no verified host name", "203.0.113.9" ],
        [ "REVERSE_DNS_NONE", 2.0, "No reverse DNS for the sending server" ], [ "ATTACHMENT_RISKY_EXTENSION", 2.0, "Risky attachment type" ],
        [ "CLIENT_LISTED", 1.0, nil ] ] },
      event.particulars)
  end

  test "a null sender is sent as <>" do
    email = create_inbound_email(mail_from: "")

    MailScore::Client.any_instance.expects(:check).with { |_raw, **envelope| envelope[:from] == "<>" }.returns(verdict)

    email.score_now
  end

  test "mail already scored is not scored again" do
    email = create_inbound_email
    MailScore::Client.any_instance.expects(:check).once.returns(verdict)

    email.score_now
    email.reload.score_now

    assert email.scored?
    assert_equal 1, email.events.where(action: "inbound_email_scored").count
  end

  test "mail with no message left is not scored" do
    email = create_inbound_email
    email.raw_email.purge
    MailScore::Client.any_instance.expects(:check).never

    email.reload.score_now

    assert_not email.scored?
  end

  test "the verdict reaches no webhook, not even one subscribed to everything" do
    webhooks(:active).update!(subscribed_actions: Webhook::PERMITTED_ACTIONS)
    email = create_inbound_email
    MailScore::Client.any_instance.stubs(:check).returns(verdict(action: :reject, score: 20.0))

    assert_not_includes Webhook::PERMITTED_ACTIONS, "inbound_email_scored"
    assert_no_difference -> { Webhook::Delivery.count } do
      perform_enqueued_jobs only: Event::WebhookDispatchJob do
        email.score_now
      end
    end
  end

  private
    def verdict(action: :no_action, score: 0.0, complete: true, symbols: [])
      MailScore::Client::Result.new(action:, score:, complete:, symbols:, smtp_reply: nil, subject: nil)
    end

    def symbol(name, weight, detail, description)
      MailScore::Client::Result::Symbol.new(name:, weight:, detail:, description:)
    end
end
