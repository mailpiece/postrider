require "test_helper"

class Contacts::ScreenedOutMailsControllerTest < ActionDispatch::IntegrationTest
  test "destroy erases the mail in the background" do
    sign_in_as :leo

    assert_enqueued_with job: User::EraseScreenedOutMailJob, args: [ users(:leo) ] do
      delete contacts_screened_out_mail_path
    end

    assert_redirected_to contacts_denied_path
  end

  test "destroy is for admins" do
    sign_in_as :nonstaff

    assert_no_enqueued_jobs only: User::EraseScreenedOutMailJob do
      delete contacts_screened_out_mail_path
    end

    assert_response :forbidden
  end
end
