require "test_helper"

class InboundEmail::ScoreJobTest < ActiveJob::TestCase
  setup do
    @email = create_inbound_email
  end

  test "records the verdict" do
    MailScore::Client.any_instance.stubs(:check).returns(
      MailScore::Client::Result.new(action: :no_action, score: 1.5, complete: true, symbols: [], smtp_reply: nil, subject: nil))

    InboundEmail::ScoreJob.perform_now(@email)

    assert_equal "no_action", @email.events.find_by!(action: "inbound_email_scored").particulars["action"]
  end

  test "retries an unreachable scorer a few times, then gives up quietly" do
    MailScore::Client.any_instance.expects(:check).times(5).raises(MailScore::Client::Unreachable, "connection refused")

    assert_nothing_raised do
      perform_enqueued_jobs { InboundEmail::ScoreJob.perform_later(@email) }
    end

    assert_not @email.scored?
  end

  test "drops a message the scorer refuses without retrying" do
    MailScore::Client.any_instance.expects(:check).once.raises(MailScore::Client::Error.new("unauthorized", status: 401))

    assert_nothing_raised do
      perform_enqueued_jobs { InboundEmail::ScoreJob.perform_later(@email) }
    end

    assert_not @email.scored?
  end

  test "mail deleted before its turn discards the job" do
    InboundEmail::ScoreJob.perform_later(@email)
    @email.destroy!

    assert_nothing_raised do
      perform_enqueued_jobs only: InboundEmail::ScoreJob
    end
  end
end
