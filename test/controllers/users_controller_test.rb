require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "index lets an admin change everyone but themselves" do
    get users_path

    assert_response :success
    assert_select "#user_#{users(:leo).id} .step__actions input[name=?][disabled]", "user[role]"
    assert_select "#user_#{users(:nonstaff).id} .step__actions form[action=?] input[type=checkbox][name=?]:not([disabled])", user_role_path(users(:nonstaff)), "user[role]"
  end

  test "index gives a member nothing to change" do
    sign_out
    sign_in_as :nonstaff

    get users_path

    assert_response :success
    assert_select ".step__actions input[type=checkbox]:not([disabled])", count: 0
    assert_select ".step__actions button", count: 0
  end

  test "index json answers with the same people" do
    get users_path, as: :json

    assert_response :success
    assert_equal accounts(:davids_account).users.active.alphabetically.map(&:id), response.parsed_body.map { |row| row["id"] }
  end

  test "show of one's own profile offers to edit it and sign out" do
    get user_path(users(:leo))

    assert_response :success
    assert_select "turbo-frame#user_identity form[action=?] input[name=?]", user_path(users(:leo)), "user[name]"
    assert_select "button", text: "Sign out"
  end

  test "show of someone else offers a member nothing" do
    logout_and_sign_in_as :nonstaff

    get user_path(users(:leo))

    assert_response :success
    assert_select ".settings form", count: 0
    assert_select "#session_transfer_url", count: 0
  end

  test "show of a teammate offers an admin to issue their sign-in link, without minting one" do
    confirm_sudo

    assert_no_difference -> { identities(:nonstaff).transfers.count } do
      get user_path(users(:nonstaff))
    end

    assert_response :success
    assert_select "#session_transfer_url", count: 0
    assert_select "form[action=?] button", user_transfer_token_path(users(:nonstaff)), text: "Show their sign-in link"
  end

  test "show of a teammate gives an admin the sign-in link they issued" do
    confirm_sudo
    identities(:nonstaff).transfers.create!(issuer: users(:leo))

    get user_path(users(:nonstaff))

    assert_response :success
    token = css_select("#session_transfer_url").first["value"].split("/").last
    assert_equal identities(:nonstaff), Identity.find_by_transfer_id(token)
  end

  test "show of a teammate who belongs to another account too gives no sign-in link" do
    confirm_sudo

    identities(:nonstaff).join(accounts(:other_account))

    get user_path(users(:nonstaff))

    assert_response :success
    assert_select "#session_transfer_url", count: 0
  end

  test "show of a teammate asks an admin to confirm before their sign-in link" do
    assert_no_difference -> { identities(:nonstaff).transfers.count } do
      get user_path(users(:nonstaff))
    end

    assert_response :success
    assert_select "#session_transfer_url", count: 0
    assert_select "a[href=?]", new_my_sudo_path
  end

  test "show is not found for another account's user" do
    get user_path(users(:other))

    assert_response :not_found
  end

  test "update renames oneself" do
    sign_out
    sign_in_as :nonstaff

    patch user_path(users(:nonstaff)), params: { user: { name: "New Name", role: "owner" } }

    assert_redirected_to user_path(users(:nonstaff))
    assert_equal "New Name", users(:nonstaff).reload.name
    assert users(:nonstaff).member?
  end

  test "update from the frame answers in place" do
    patch user_path(users(:leo)), params: { user: { name: "New Name" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :success
    assert_equal "New Name", users(:leo).reload.name
  end

  test "update with a blank name is refused" do
    patch user_path(users(:leo)), params: { user: { name: "" } }

    assert_response :unprocessable_entity
    assert_equal "Leo", users(:leo).reload.name
  end

  test "update of someone else is refused to a member" do
    sign_out
    sign_in_as :nonstaff

    patch user_path(users(:leo)), params: { user: { name: "Renamed" } }

    assert_response :forbidden
    assert_equal "Leo", users(:leo).reload.name
  end

  test "destroy removes a person and goes back to the people" do
    delete user_path(users(:nonstaff))

    assert_redirected_to users_path
    assert_not users(:nonstaff).reload.active?
  end

  test "destroy is refused to a member" do
    sign_out
    sign_in_as :nonstaff

    delete user_path(users(:leo))

    assert_response :forbidden
    assert users(:leo).reload.active?
  end
end
