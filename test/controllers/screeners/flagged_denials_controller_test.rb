require "test_helper"

class Screeners::FlaggedDenialsControllerTest < ActionDispatch::IntegrationTest
  setup do
    inbound_emails(:held).update!(contact: contacts(:pending))
    @flagged = flag_sender domains(:example), "bulk@sender.example"
  end

  test "create denies the pending senders the spam check flagged, and nobody else" do
    sign_in_as :leo

    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      assert_changes -> { @flagged.reload.decision }, from: "pending", to: "denied" do
        assert_no_changes -> { [ contacts(:pending).reload.decision, contacts(:approved).reload.decision ] } do
          post screener_flagged_denial_path
        end
      end
    end

    assert_redirected_to screener_path
  end

  test "create leaves flagged senders on a domain you cannot reach" do
    sign_in_as :nonstaff
    hidden = flag_sender domains(:private), "hidden-bulk@sender.example"

    assert_no_changes -> { hidden.reload.decision } do
      post screener_flagged_denial_path, as: :json
    end

    assert_response :no_content
    assert @flagged.reload.denied?
  end

  private
    def flag_sender(domain, email)
      domain.contacts.create!(email: email, decision: :pending).tap do |contact|
        create_inbound_email(domain: domain, status: :held, contact: contact)
          .track_event "scored", action: "reject", score: 7.4, complete: true, symbols: []
      end
    end
end
