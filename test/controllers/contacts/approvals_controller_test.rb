require "test_helper"

class Contacts::ApprovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "create approves the contact and forwards their held mail" do
    assert_enqueued_jobs 1, only: Contact::ForwardHeldJob do
      assert_changes -> { contacts(:denied).reload.decision }, from: "denied", to: "approved" do
        post contact_approval_path(contacts(:denied))
      end
    end

    assert_redirected_to contacts_path
  end

  test "destroy denies the contact" do
    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      assert_changes -> { contacts(:approved).reload.decision }, from: "approved", to: "denied" do
        delete contact_approval_path(contacts(:approved))
      end
    end

    assert_redirected_to contacts_path
  end

  test "create returns to the page it was switched from" do
    post contact_approval_path(contacts(:denied)), headers: { "HTTP_REFERER" => contact_url(contacts(:denied)) }

    assert_redirected_to contact_url(contacts(:denied))
  end

  test "a yes in the Screener returns to it" do
    post contact_approval_path(contacts(:pending)), headers: { "HTTP_REFERER" => screener_url }

    assert_redirected_to screener_url
    assert contacts(:pending).reload.approved?
  end

  test "create as JSON" do
    assert_changes -> { contacts(:denied).reload.decision }, from: "denied", to: "approved" do
      post contact_approval_path(contacts(:denied)), as: :json
    end

    assert_response :no_content
  end

  test "destroy as JSON" do
    assert_changes -> { contacts(:pending).reload.decision }, from: "pending", to: "denied" do
      delete contact_approval_path(contacts(:pending)), as: :json
    end

    assert_response :no_content
  end

  test "cannot decide for a contact on a domain you cannot reach" do
    accesses(:private_leo).destroy

    assert_no_changes -> { contacts(:private).reload.decision } do
      post contact_approval_path(contacts(:private))
    end

    assert_response :not_found
  end

  test "cannot decide for another account's contact" do
    assert_no_changes -> { contacts(:other_account).reload.decision } do
      post contact_approval_path(contacts(:other_account))
    end

    assert_response :not_found
  end
end
