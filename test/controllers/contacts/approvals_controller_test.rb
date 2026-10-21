require "test_helper"

class Contacts::ApprovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "create approves the contact and forwards their held mail" do
    contact = contacts(:denied)

    assert_enqueued_jobs 1, only: Contact::ForwardHeldJob do
      post contact_approval_path(contact)
    end

    assert_redirected_to contacts_path
    assert contact.reload.approved?
  end

  test "destroy denies the contact" do
    contact = contacts(:approved)

    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      delete contact_approval_path(contact)
    end

    assert_redirected_to contacts_path
    assert contact.reload.denied?
  end

  test "create returns to the list it was switched from" do
    post contact_approval_path(contacts(:denied)), headers: { "HTTP_REFERER" => contacts_denied_url }

    assert_redirected_to contacts_denied_url
  end

  test "create replaces the contact for turbo" do
    contact = contacts(:denied)

    post contact_approval_path(contact), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", ActionView::RecordIdentifier.dom_id(contact)
    assert_match "Now forwarding mail from stranger@sender.example", response.body
  end

  test "destroy replaces the contact for turbo" do
    contact = contacts(:approved)

    delete contact_approval_path(contact), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", ActionView::RecordIdentifier.dom_id(contact)
    assert_match "Now holding mail from friend@sender.example", response.body
  end

  test "create as JSON" do
    contact = contacts(:denied)

    post contact_approval_path(contact), as: :json

    assert_response :no_content
    assert contact.reload.approved?
  end

  test "destroy as JSON" do
    contact = contacts(:approved)

    delete contact_approval_path(contact), as: :json

    assert_response :no_content
    assert contact.reload.denied?
  end

  test "cannot decide for a contact on a domain you cannot reach" do
    accesses(:private_leo).destroy
    contact = contacts(:private)

    post contact_approval_path(contact)

    assert_response :not_found
    assert contact.reload.denied?
  end

  test "cannot decide for another account's contact" do
    contact = contacts(:other_account)

    post contact_approval_path(contact)

    assert_response :not_found
    assert contact.reload.denied?
  end
end
