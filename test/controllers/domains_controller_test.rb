require "test_helper"

class DomainsControllerTest < ActionDispatch::IntegrationTest
  test "index lists every domain the user reaches" do
    sign_in_as :leo
    missing = Current.account.domains.create!(name: "missing.example", creator: users(:leo), dkim_status: :missing)

    get domains_path

    assert_response :success
    assert_select "li##{dom_id(missing)}"
    assert_select "li##{dom_id(domains(:other_account))}", count: 0
  end

  test "index says so when the user reaches no domain" do
    sign_in_as :leo
    users(:leo).accesses.delete_all

    get domains_path

    assert_response :success
    assert_select ".blank-slate", text: "Add every domain this relay sends and receives mail for."
  end

  test "index as JSON lists the same domains, leaving out one you cannot reach" do
    sign_in_as :leo

    get domains_path, as: :json

    assert_response :success
    assert_equal [ domains(:unverified).id, domains(:example).id, domains(:private).id ], response.parsed_body.pluck("id")
  end

  test "index as JSON says whether each domain receives and sends" do
    sign_in_as :leo
    domains(:private).update!(sending: false)

    get domains_path, as: :json

    assert_equal [ true, true, false ], response.parsed_body.pluck("sending")
  end

  test "the domain page gives a member no rows and no removing" do
    domain = domains(:example)
    sign_in_as :nonstaff

    get domain_path(domain)

    assert_response :success
    assert_select ".settings__rows", count: 0
    assert_select "form[action=?]", domain_path(domain), count: 0
  end

  test "the domain page has no settings page beside it" do
    sign_in_as :leo

    get "#{domain_path(domains(:example))}/edit"

    assert_response :not_found
  end

  test "the domain page tells an admin the blocked phrases changed" do
    domain = domains(:example)
    domain.update!(blocked_phrases: "free money")
    sign_in_as :leo

    get domain_path(domain)

    assert_select ".trail__sentence", text: "Blocked phrases changed"
  end

  test "the domain page keeps a change to the blocked phrases from a member" do
    domain = domains(:example)
    domain.update!(blocked_phrases: "free money")
    sign_in_as :nonstaff

    get domain_path(domain)

    assert_select ".trail__sentence", text: "Blocked phrases changed", count: 0
    assert_not_includes response.body, "free money"
  end

  test "the domain page keeps a change to the allowed IPs from a member" do
    domain = domains(:example)
    domain.update!(allowed_ips: "203.0.113.0/24")
    sign_in_as :nonstaff

    get domain_path(domain)

    assert_select ".trail__sentence", text: "Allowed IPs changed", count: 0
  end

  test "the domain page tells an admin a sending token was refused" do
    domain = domains(:example)
    Event.create!(eventable: domain, domain: domain, action: "sending_token_refused", particulars: { token_name: "Example sending token", ip: "198.51.100.12" })
    sign_in_as :leo

    get domain_path(domain)

    assert_select ".trail__sentence", text: "Refused sending token Example sending token from 198.51.100.12, not in Allowed IPs"
  end

  test "the domain page keeps a refused sending token from a member" do
    domain = domains(:example)
    Event.create!(eventable: domain, domain: domain, action: "sending_token_refused", particulars: { token_name: "Example sending token", ip: "198.51.100.12" })
    sign_in_as :nonstaff

    get domain_path(domain)

    assert_not_includes response.body, "198.51.100.12"
  end

  test "json renders DNS statuses as lowercase enum keys" do
    sign_in_as :leo
    domain = domains(:unverified)
    domain.update!(mx_status: :ok, dkim_status: :missing)

    get domain_path(domain), as: :json

    assert_response :success
    assert_equal "ok", response.parsed_body["mx_status"]
    assert_equal "missing", response.parsed_body["dkim_status"]
    assert_nil response.parsed_body["dmarc_status"]
  end

  test "show and create render json" do
    sign_in_as :leo
    confirm_sudo

    get domain_path(domains(:example)), as: :json
    assert_response :success
    assert_equal "example.com", response.parsed_body["name"]
    assert_equal true, response.parsed_body["receiving"]
    assert_equal true, response.parsed_body["sending"]

    assert_difference -> { Current.account.domains.count }, 1 do
      post domains_path, params: { domain: { name: "created-via-json.example" } }, as: :json
    end
    assert_response :created
    assert_equal "created-via-json.example", response.parsed_body["name"]
  end

  test "adding a domain asks for a passkey first" do
    sign_in_as :leo

    get new_domain_path

    assert_redirected_to new_my_sudo_path
  end

  test "destroy asks the browser to confirm, then removes the domain, and its mail after" do
    domain = domains(:example)
    create_delivery
    sign_in_as :leo

    get domain_path(domain)
    assert_select "form[action=?] [data-turbo-confirm]", domain_path(domain)

    assert_difference -> { Domain.count }, -1 do
      assert_enqueued_jobs 2, only: Domain::PurgeMailJob do
        delete domain_path(domain)
      end
    end
    assert_redirected_to domains_path
  end

  test "destroy over json without confirm keeps the domain and says what to send" do
    sign_in_as :leo

    assert_no_difference -> { Domain.count } do
      delete domain_path(domains(:example)), as: :json
    end

    assert_response :unprocessable_entity
    assert_match "confirm", response.parsed_body["error"]
  end

  test "destroy over json with confirm, in any case and spacing, answers with no content and purges the mail later" do
    create_delivery
    sign_in_as :leo

    assert_difference -> { Current.account.domains.count }, -1 do
      assert_enqueued_jobs 2, only: Domain::PurgeMailJob do
        delete domain_path(domains(:example)), params: { confirm: " Example.COM " }, as: :json
      end
    end

    assert_response :no_content
  end

  test "show is not found for another account's domain" do
    sign_in_as :leo

    get domain_path(domains(:other_account))

    assert_response :not_found
  end
end
