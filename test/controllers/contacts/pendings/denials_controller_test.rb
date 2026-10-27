require "test_helper"

class Contacts::Pendings::DenialsControllerTest < ActionDispatch::IntegrationTest
  test "create denies everyone pending, and nobody else" do
    sign_in_as :leo

    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      assert_changes -> { contacts(:pending).reload.decision }, from: "pending", to: "denied" do
        assert_no_changes -> { contacts(:approved).reload.decision } do
          post contacts_pending_denial_path
        end
      end
    end

    assert_redirected_to contacts_pending_path
  end

  test "create leaves pending contacts on a domain you cannot reach" do
    sign_in_as :nonstaff
    contacts(:private).update!(decision: :pending)

    assert_no_changes -> { contacts(:private).reload.decision } do
      post contacts_pending_denial_path, as: :json
    end

    assert_response :no_content
    assert contacts(:pending).reload.denied?
  end
end
