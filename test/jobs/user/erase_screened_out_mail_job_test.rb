require "test_helper"

class User::EraseScreenedOutMailJobTest < ActiveJob::TestCase
  test "erases the user's screened-out mail" do
    held = inbound_emails(:held)

    User::EraseScreenedOutMailJob.perform_now(users(:leo))

    assert_not InboundEmail.exists?(held.id)
  end
end
