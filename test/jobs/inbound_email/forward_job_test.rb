require "test_helper"

class InboundEmail::ForwardJobTest < ActiveJob::TestCase
  test "an inbound email deleted mid-flight discards its job instead of raising" do
    inbound_email = inbound_emails(:received)
    InboundEmail::ForwardJob.perform_later(inbound_email, ip: "10.0.0.1", helo: "mail.example.com")
    inbound_email.destroy!

    assert_nothing_raised do
      perform_enqueued_jobs only: InboundEmail::ForwardJob
    end
  end
end
