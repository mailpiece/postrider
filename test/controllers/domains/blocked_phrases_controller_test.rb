require "test_helper"

class Domains::BlockedPhrasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "an admin opens the blocked phrases" do
    @domain.update!(blocked_phrases: "free money")
    sign_in_as :leo

    get domain_blocked_phrases_path(@domain)

    assert_response :success
    assert_select "form[action=?] textarea", domain_blocked_phrases_path(@domain), text: /free money/
  end

  test "an admin saves the blocked phrases" do
    sign_in_as :leo

    patch domain_blocked_phrases_path(@domain), params: { domain: { blocked_phrases: "free money\r\n\r\nact now" } }

    assert_redirected_to domain_path(@domain)
    assert_equal "free money\nact now", @domain.reload.blocked_phrases
  end

  test "a phrase that is too short is turned down in place, keeping what was typed" do
    sign_in_as :leo

    patch domain_blocked_phrases_path(@domain), params: { domain: { blocked_phrases: "free money\r\nabc" } }

    assert_response :unprocessable_entity
    assert_select ".error-explanation__message", text: /a phrase needs at least #{Domain::MIN_PHRASE_LENGTH} characters/
    assert_select "textarea", text: /free money\s+abc/
    assert_nil @domain.reload.blocked_phrases
  end

  test "a member cannot change the blocked phrases" do
    sign_in_as :nonstaff

    patch domain_blocked_phrases_path(@domain), params: { domain: { blocked_phrases: "free money" } }

    assert_response :forbidden
    assert_nil @domain.reload.blocked_phrases
  end

  test "another account's domain cannot be reached" do
    sign_in_as :leo

    patch domain_blocked_phrases_path(domains(:other_account)), params: { domain: { blocked_phrases: "free money" } }

    assert_response :not_found
  end
end
