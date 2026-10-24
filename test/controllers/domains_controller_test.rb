require "test_helper"

class DomainsControllerTest < ActionDispatch::IntegrationTest
  test "index lists the verified domains and nothing else" do
    sign_in_as :leo
    missing = Current.account.domains.create!(name: "missing.example", creator: users(:leo), dkim_status: :missing)

    get domains_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Domains"
    assert_select "a[href=?]", new_domain_path
    assert_select "li##{dom_id(domains(:example))}"
    assert_select ".filter__empty a[href=?]", search_path
    assert_select ".rows .row[data-quick-find-target=item]"
    [ missing, domains(:unverified) ].each { |domain| assert_select "li##{dom_id(domain)}", count: 0 }
  end

  test "index keeps the up hotkey off a crumb that leads out of the account" do
    sign_in_as :leo
    users(:leo).identity.users.create! account: accounts(:other_account), name: "Elsewhere", role: :member

    get domains_path

    assert_select "a.breadcrumbs__home[href=?]:not([data-controller])", "/session/menu"
  end

  test "index counts the domains not verified, over the list" do
    sign_in_as :leo
    Current.account.domains.create!(name: "missing.example", creator: users(:leo), dkim_status: :missing)

    get domains_path

    assert_select ".rows--links a[href=?]", domains_unverified_path, text: "Not verified"
    assert_select ".rows--links .row__end", text: "2"
    assert_select ".rows--links + .rows__section .rows__heading", text: "Verified"
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
  end

  test "index says so when no domain is verified" do
    sign_in_as :leo
    Current.account.domains.update_all(dkim_status: nil)

    get domains_path

    assert_response :success
    assert_select ".blank-slate", text: "No verified domains."
    assert_select ".rows--links a[href=?]", domains_unverified_path
    assert_select ".rows--links + .blank-slate"
  end

  test "the navigation's Domains link opens the verified domains" do
    sign_in_as :leo

    get domains_path

    assert_select "a.site-header__link[href=?][aria-current=page]", domains_path, text: /Domains/
  end

  test "index as JSON lists the same domains, leaving out one you cannot reach" do
    sign_in_as :leo

    get domains_path, as: :json

    assert_response :success
    assert_equal [ domains(:example).id, domains(:private).id ], response.parsed_body.pluck("id")
  end

  test "index as JSON says whether each domain receives and sends" do
    sign_in_as :leo
    domains(:private).update!(sending: false)

    get domains_path, as: :json

    assert_equal [ true, false ], response.parsed_body.pluck("sending")
  end

  test "settings lists the domain's settings as rows" do
    sign_in_as :leo

    get edit_domain_path(domains(:example))

    assert_response :success
    assert_equal [ "DNS records", "People" ], css_select(".settings__rows .row__title").map(&:text)
  end

  test "the domain page hides the admin toolbar from a member" do
    domain = domains(:example)
    sign_in_as :nonstaff

    get domain_path(domain)

    assert_response :success
    assert_select ".project__title", text: "example.com"
    assert_select "a.tool", count: 0
    assert_select "a[href=?]", edit_domain_path(domain), count: 0
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

  test "a member cannot open domain settings" do
    sign_in_as :nonstaff

    get edit_domain_path(domains(:example))

    assert_response :forbidden
  end

  test "the domain page links an admin to the domain's resources, settings and DNS records" do
    sign_in_as :leo
    domain = domains(:unverified)

    get domain_path(domain)

    assert_select "a.tool[href=?] .tool__title", domain_sending_tokens_path(domain), text: "Sending tokens"
    assert_select "a.tool[href=?] .row__meta", domain_mailboxes_path(domain), text: "Required", count: 2
    assert_select "a.tool[href=?] .blank-slate", domain_webhooks_path(domain), text: /No webhooks yet/
    assert_select "a.tool[href=?] .blank-slate", domain_blocked_phrases_path(domain), text: /No blocked phrases yet/
    assert_select "a.tool[href=?] .blank-slate", domain_allowed_ips_path(domain), text: /Any IP can send through the API/
    assert_select ".strip a[href=?]", edit_domain_path(domain), text: "Settings"
    assert_select ".project__header a[href=?]", domain_dns_records_path(domain), text: "See the DNS records"
    assert_select ".project__description", text: "Its DNS records have not been checked yet."
    assert_select ".trail__sentence", text: "#{users(:leo).name} added this domain"
  end

  test "the domain page says a record could not be looked up rather than never checked" do
    sign_in_as :leo
    domain = domains(:example)
    domain.update!(mx_error: "DNS timeout", dns_checked_at: Time.current)

    get domain_path(domain)

    assert_select ".project__description",
      text: "Does not receive mail yet: the inbound record could not be looked up (DNS timeout). Verified for sending."
  end

  test "the unverified list renders DNS statuses as human-readable labels" do
    sign_in_as :leo
    domain = domains(:unverified)
    domain.update!(mx_status: :ok, dkim_status: :missing, dmarc_status: :invalid, dns_checked_at: Time.current)

    get domains_unverified_path
    assert_response :success
    assert_select ".row__meta", text: /Not verified · DNS problems · DKIM record is missing · DMARC record is not valid · checked/
    assert_select ".row__meta .status", text: "DNS problems"
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

  test "destroy leads back to the domains" do
    sign_in_as :leo

    delete domain_path(domains(:unverified))

    assert_redirected_to domains_path
  end

  test "destroy answers json with no content" do
    sign_in_as :leo

    assert_difference -> { Current.account.domains.count }, -1 do
      delete domain_path(domains(:unverified)), as: :json
    end

    assert_response :no_content
  end

  test "show is not found for another account's domain" do
    sign_in_as :leo

    get domain_path(domains(:other_account))

    assert_response :not_found
  end
end
