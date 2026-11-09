require "test_helper"

class Mailpieces::DeferredsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists the deferred mail" do
    get mailpieces_deferred_path

    assert_response :success
    assert_select "li##{dom_id(mailpieces(:deferred))}"
  end

  test "show as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    deferred = mailpieces(:deferred)
    hidden = deliver_from(domains(:private), status: "deferred").mailpiece

    get mailpieces_deferred_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("id"), deferred.id
    assert_not_includes response.parsed_body.pluck("id"), hidden.id
  end
end
