require "test_helper"

class My::AccessTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "index renders untenanted" do
    untenanted { get my_access_tokens_path }

    assert_response :success
    assert_select "a.breadcrumbs__home[href=?]", "/session/menu"
  end

  test "index renders in an account" do
    get my_access_tokens_path

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", user_path(users(:leo)), text: "Profile"
  end

  test "new asks for a passkey first" do
    get new_my_access_token_path
    assert_redirected_to new_my_sudo_path

    confirm_sudo
    get new_my_access_token_path
    assert_response :success
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
  end

  test "create reveals the token in the response" do
    confirm_sudo

    assert_difference -> { identities(:leo).access_tokens.count }, +1 do
      post my_access_tokens_path, params: { access_token: { description: "GitHub", permission: "read" } }
    end

    assert_response :created
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_revealed identities(:leo).access_tokens.order(:created_at).last
  end

  test "create from the form reveals the token in a turbo stream" do
    confirm_sudo

    post my_access_tokens_path, params: { access_token: { description: "GitHub", permission: "write" } }, as: :turbo_stream

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "turbo-stream[action=replace][target=?]", "new_access_token"
    assert_revealed identities(:leo).access_tokens.order(:created_at).last
  end

  test "a created token is revealed once, and no page shows it again" do
    confirm_sudo

    post my_access_tokens_path, params: { access_token: { description: "GitHub", permission: "read" } }
    token = token_in_body
    access_token = identities(:leo).access_tokens.order(:created_at).last

    get "/my/access_tokens/#{access_token.id}"
    assert_response :not_found

    get my_access_tokens_path
    assert_response :success
    assert_not_includes response.body, token
  end

  test "create via JSON returns the token, uncached" do
    confirm_sudo

    post my_access_tokens_path, params: { access_token: { description: "CLI", permission: "write" } }, as: :json

    assert_response :created
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal Identity::AccessToken.find(response.parsed_body["id"]), Identity::AccessToken.authenticate(response.parsed_body["token"])
  end

  test "the passkey check lapses after thirty minutes" do
    confirm_sudo

    travel Session::SUDO_DURATION + 1.second do
      get new_my_access_token_path
    end

    assert_redirected_to new_my_sudo_path
  end

  private
    def token_in_body
      response.body[/value="(\w+)" id="access-token"/, 1]
    end

    def assert_revealed(access_token)
      assert_equal access_token, Identity::AccessToken.authenticate(token_in_body)
      assert_match(/<div id="new_access_token"[^>]* data-turbo-temporary[ >]/, response.body)
    end
end
