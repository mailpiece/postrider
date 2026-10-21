require "test_helper"

class DnsCheckJobTest < ActiveJob::TestCase
  test "runs the DNS check on the subject" do
    subject = mock
    subject.expects(:check_dns).once

    DnsCheckJob.perform_now(subject)
  end
end
