require "test_helper"

class SendingTokensControllerTest < ActionDispatch::IntegrationTest
  test "an API client with a write access token provisions a sending token and gets the secret once" do
    assert_difference -> { domains(:example).sending_tokens.count }, 1 do
      post domain_sending_tokens_path(domains(:example)), params: { sending_token: { name: "Mailer" } }, headers: api_token_env, as: :json
    end

    assert_response :created
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    token = domains(:example).sending_tokens.order(:created_at).last
    assert_equal token.id, body["id"]
    assert_equal "Mailer", body["name"]
    assert body["token"].present?
    assert_equal token, SendingToken.authenticate(body["token"])
    assert_equal domains(:example).name, body["domain"]
  end

  test "the API lists a domain's sending tokens without ever exposing their secrets" do
    token = sending_tokens(:example)

    get domain_sending_tokens_path(domains(:example)), headers: api_token_env, as: :json

    assert_response :success
    entry = response.parsed_body.find { |t| t["id"] == token.id }
    assert_equal "Example sending token", entry["name"]
    assert_not entry.key?("token")
  end

  test "the API shows a sending token without exposing its secret" do
    token = sending_tokens(:example)

    get domain_sending_token_path(domains(:example), token), headers: api_token_env, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal token.id, body["id"]
    assert_equal "Example sending token", body["name"]
    assert_equal domains(:example).name, body["domain"]
    assert_not body.key?("token")
  end

  test "the API revokes a sending token" do
    token = sending_tokens(:example)

    assert_difference -> { domains(:example).sending_tokens.count }, -1 do
      delete domain_sending_token_path(domains(:example), token), headers: api_token_env, as: :json
    end

    assert_response :no_content
  end

  test "a read-only access token cannot provision a sending token" do
    read_only = identities(:leo).access_tokens.create!(permission: :read, description: "Read only")

    assert_no_difference -> { domains(:example).sending_tokens.count } do
      post domain_sending_tokens_path(domains(:example)), params: { sending_token: { name: "Nope" } },
        headers: bearer_token_env(read_only.token), as: :json
    end

    assert_response :unauthorized
  end

  test "an unauthenticated request cannot provision a sending token" do
    assert_no_difference -> { domains(:example).sending_tokens.count } do
      post domain_sending_tokens_path(domains(:example)), params: { sending_token: { name: "Nope" } }, as: :json
    end

    assert_not_equal 201, response.status
  end

  test "a member cannot provision a sending token" do
    member_token = identities(:nonstaff).access_tokens.create!(permission: :write, description: "Member")

    assert_no_difference -> { SendingToken.count } do
      post domain_sending_tokens_path(domains(:private)), params: { sending_token: { name: "Nope" } },
        headers: bearer_token_env(member_token.token), as: :json
    end

    assert_response :not_found
  end

  test "another account's domain cannot be provisioned against" do
    assert_no_difference -> { SendingToken.count } do
      post domain_sending_tokens_path(domains(:other_account)), params: { sending_token: { name: "Sneaky" } }, headers: api_token_env, as: :json
    end

    assert_response :not_found
  end

  test "new names the sending token in its heading field" do
    sign_in_as :leo
    confirm_sudo

    get new_domain_sending_token_path(domains(:example))

    assert_response :success
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "form[action=?] input[name=?][placeholder=?]", domain_sending_tokens_path(domains(:example)), "sending_token[name]", "Name this sending token…"
  end

  test "creating a sending token in the browser reveals the secret in the response" do
    sign_in_as :leo
    confirm_sudo

    assert_difference -> { domains(:example).sending_tokens.count }, 1 do
      post domain_sending_tokens_path(domains(:example)), params: { sending_token: { name: "Mailer" } }
    end

    assert_response :created
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_revealed domains(:example).sending_tokens.order(:created_at).last
  end

  test "creating a sending token from the form reveals the secret in a turbo stream" do
    sign_in_as :leo
    confirm_sudo

    post domain_sending_tokens_path(domains(:example)), params: { sending_token: { name: "Mailer" } }, as: :turbo_stream

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "turbo-stream[action=replace][target=?]", "new_sending_token"
    assert_revealed domains(:example).sending_tokens.order(:created_at).last
  end

  test "a created sending token is revealed once, and no page shows it again" do
    sign_in_as :leo
    confirm_sudo

    post domain_sending_tokens_path(domains(:example)), params: { sending_token: { name: "Mailer" } }
    secret = secret_in_body
    sending_token = domains(:example).sending_tokens.order(:created_at).last

    get domain_sending_token_path(domains(:example), sending_token)
    assert_response :success
    assert_not_includes response.body, secret

    get domain_sending_tokens_path(domains(:example))
    assert_response :success
    assert_not_includes response.body, secret
  end

  test "creating a sending token in the browser asks for a passkey first" do
    sign_in_as :leo

    assert_no_difference -> { SendingToken.count } do
      post domain_sending_tokens_path(domains(:example)), params: { sending_token: { name: "Mailer" } }
    end

    assert_redirected_to new_my_sudo_path
  end

  test "index lists the sending tokens, and says so when there are none" do
    sign_in_as :leo

    get domain_sending_tokens_path(domains(:private))
    assert_select ".blank-slate", text: "No sending tokens yet."

    get domain_sending_tokens_path(domains(:example))

    assert_response :success
    assert_select "input[placeholder=?]", "Filter sending tokens…"
    assert_select ".filter__empty a", count: 0
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select "li.row[data-quick-find-target=item] .row__title", text: "Example sending token"
  end

  test "show renders the persistent sending token page without the secret" do
    sign_in_as :leo
    get domain_sending_token_path(domains(:example), sending_tokens(:example))

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Example sending token"
    assert_select ".trail__sentence", text: "Sending token created"
    assert_select "input[readonly]", count: 0
    assert_select ".details__value code", text: "POST #{messages_url}"
    assert_includes messages_url, "/#{accounts(:davids_account).external_account_id}/messages"
  end

  private
    def secret_in_body
      response.body[/value="(postrider_\w+)"/, 1]
    end

    def assert_revealed(sending_token)
      assert_equal sending_token, SendingToken.authenticate(secret_in_body)
      assert_match(/<div id="new_sending_token"[^>]* data-turbo-temporary[ >]/, response.body)
    end
end
