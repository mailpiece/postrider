require "test_helper"

class Contacts::DeniedsControllerTest < ActionDispatch::IntegrationTest
  test "show lists the screened-out senders, each linking to their page" do
    sign_in_as :leo

    get contacts_denied_path

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".breadcrumbs strong", text: "Screened out"
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select "#contact_#{contacts(:denied).id} a.row__body[href=?]", contact_path(contacts(:denied)), text: /stranger@sender\.example.*1 email held/m
    assert_select "#contact_#{contacts(:pending).id}", count: 0
    assert_select ".envelope--strip, .screener-card__email", count: 0
  end

  test "show screens a sender back in, asking first" do
    sign_in_as :leo

    get contacts_denied_path

    assert_select "form[action=?][data-turbo-confirm=?] button", contact_approval_path(contacts(:denied)),
      "Forward 1 held email from stranger@sender.example to forwarding@elsewhere.example?", text: "Screen them in"
    assert_select "form[action=?] button", contact_approval_path(contacts(:denied)), text: "No", count: 0
  end

  test "show asks an admin before clearing all" do
    sign_in_as :leo

    get contacts_denied_path

    assert_select "form[action=?][data-turbo-confirm=?] button", contacts_denied_path,
      "Erase all 1 email from screened-out senders? This can't be undone. The senders stay screened out.", text: "Clear all…"
  end

  test "show offers no clearing to a member" do
    sign_in_as :nonstaff

    get contacts_denied_path

    assert_select "form[action=?]", contacts_denied_path, count: 0
  end

  test "show renders json" do
    sign_in_as :leo

    get contacts_denied_path, as: :json

    assert_response :success
    assert_equal [ "denied" ], response.parsed_body.pluck("decision").uniq
    assert_equal 1, response.parsed_body.find { it["id"] == contacts(:denied).id }["held_count"]
  end

  test "show omits senders on a domain you cannot reach" do
    sign_in_as :nonstaff

    get contacts_denied_path, as: :json

    assert_includes response.parsed_body.pluck("id"), contacts(:denied).id
    assert_not_includes response.parsed_body.pluck("id"), contacts(:private).id
  end

  test "destroy erases the mail in the background" do
    sign_in_as :leo

    assert_enqueued_with job: User::EraseScreenedOutMailJob, args: [ users(:leo) ] do
      delete contacts_denied_path
    end

    assert_redirected_to contacts_denied_path
  end

  test "destroy is for admins" do
    sign_in_as :nonstaff

    assert_no_enqueued_jobs only: User::EraseScreenedOutMailJob do
      delete contacts_denied_path
    end

    assert_response :forbidden
  end
end
