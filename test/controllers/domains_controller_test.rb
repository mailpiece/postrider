require "test_helper"

class DomainsControllerTest < ActionDispatch::IntegrationTest
  test "index lists every domain the user reaches, those not verified first, then by name" do
    sign_in_as :leo
    missing = Current.account.domains.create!(name: "missing.example", creator: users(:leo), dkim_status: :missing)

    get domains_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Domains"
    assert_select "a[href=?]", new_domain_path
    assert_select ".filter__empty a[href=?]", search_path
    assert_select ".rows .row[data-quick-find-target=item]"
    assert_equal [ missing, domains(:unverified), domains(:example), domains(:private) ].map { |domain| dom_id(domain) }, css_select(".rows li.row").pluck("id")
    assert_select "li##{dom_id(domains(:unverified))} .row__end .status", text: "Not checked"
    assert_select "li##{dom_id(domains(:other_account))}", count: 0
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
  end

  test "index keeps the up hotkey off a crumb that leads out of the account" do
    sign_in_as :leo
    users(:leo).identity.users.create! account: accounts(:other_account), name: "Elsewhere", role: :member

    get domains_path

    assert_select "a.breadcrumbs__home[href=?]:not([data-controller])", "/session/menu"
  end

  test "index no longer splits the domains by verification" do
    sign_in_as :leo

    get domains_path

    assert_select "a[href=?]", domains_unverified_path, count: 0
    assert_select ".rows__heading", count: 0
  end

  test "index says so when the user reaches no domain" do
    sign_in_as :leo
    users(:leo).accesses.delete_all

    get domains_path

    assert_response :success
    assert_select ".blank-slate", text: "Add every domain this relay sends and receives mail for."
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
    assert_equal [ domains(:unverified).id, domains(:example).id, domains(:private).id ], response.parsed_body.pluck("id")
  end

  test "index as JSON says whether each domain receives and sends" do
    sign_in_as :leo
    domains(:private).update!(sending: false)

    get domains_path, as: :json

    assert_equal [ true, true, false ], response.parsed_body.pluck("sending")
  end

  test "the domain page lists what the domain has as rows, for an admin" do
    sign_in_as :leo
    domain = domains(:example)

    get domain_path(domain)

    assert_response :success
    assert_equal [ "DNS records", "Receiving and sending", "Mailboxes", "Sending tokens", "Webhooks", "Blocked phrases", "Allowed IPs", "People" ],
      css_select(".settings__rows .row__title").map(&:text)
    assert_select ".settings__rows li.row .icon", count: 8
    assert_select ".settings__rows a[href=?] .row__meta", domain_dns_records_path(domain), text: "Verified · DNS not checked yet"
    assert_select ".settings__rows a[href=?] .row__meta", domain_switches_path(domain), text: "On"
    assert_select ".settings__rows a[href=?] .row__meta", domain_mailboxes_path(domain), text: "5 mailboxes"
    assert_select ".settings__rows a[href=?] .row__meta", domain_sending_tokens_path(domain), text: "1 sending token"
    assert_select ".settings__rows a[href=?] .row__meta", domain_webhooks_path(domain), text: "2 webhooks"
    assert_select ".settings__rows a[href=?] .row__meta", domain_blocked_phrases_path(domain), text: "None"
    assert_select ".settings__rows a[href=?] .row__meta", domain_allowed_ips_path(domain), text: "Any IP can send"
    assert_select ".settings__rows a[href=?] .row__meta", domain_people_path(domain), text: "Everyone"
    assert_select ".filter-bar input[placeholder=?]", "Filter settings…"
  end

  test "the domain page counts what a domain has and says when its DNS was checked" do
    sign_in_as :leo
    domain = domains(:private)
    domain.update!(blocked_phrases: "free money\ncheap pills", allowed_ips: "203.0.113.0/24", dns_checked_at: Time.current)

    get domain_path(domain)

    assert_select ".settings__rows a[href=?] .row__meta", domain_dns_records_path(domain), text: /\AVerified · checked/
    assert_select ".settings__rows a[href=?] .row__meta time[data-reader-time-target=timeordate]", domain_dns_records_path(domain)
    assert_select ".settings__rows a[href=?] .row__meta", domain_blocked_phrases_path(domain), text: "2 phrases"
    assert_select ".settings__rows a[href=?] .row__meta", domain_allowed_ips_path(domain), text: "1 IP"
    assert_select ".settings__rows a[href=?] .row__meta", domain_people_path(domain), text: "1 person"
  end

  test "the domain page says sending is off" do
    sign_in_as :leo
    domains(:example).update!(sending: false)

    get domain_path(domains(:example))

    assert_select ".settings__rows a[href=?] .row__meta", domain_switches_path(domains(:example)), text: "Sending off"
  end

  test "the domain page says both are off" do
    sign_in_as :leo
    domains(:example).update!(receiving: false, sending: false)

    get domain_path(domains(:example))

    assert_select ".settings__rows a[href=?] .row__meta", domain_switches_path(domains(:example)), text: "Off"
  end

  test "the domain page gives a member the history only, no rows and no removing" do
    domain = domains(:example)
    sign_in_as :nonstaff

    get domain_path(domain)

    assert_response :success
    assert_select ".breadcrumbs strong", text: "example.com"
    assert_select ".page h2", text: "History"
    assert_select ".settings__rows", count: 0
    assert_select ".filter-bar", count: 0
    assert_select ".trail__sentence", text: "#{users(:leo).name} added this domain"
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

  test "the domain page lists an unverified domain's DNS records as not verified" do
    sign_in_as :leo
    domain = domains(:unverified)

    get domain_path(domain)

    assert_select ".settings__rows a[href=?] .row__meta", domain_dns_records_path(domain), text: "Not verified · DNS not checked yet"
    assert_select ".settings__rows a[href=?] .row__meta", domain_mailboxes_path(domain), text: "2 mailboxes"
    assert_select ".settings__rows a[href=?] .row__meta", domain_webhooks_path(domain), text: "None yet"
    assert_select ".settings__rows a[href=?] .row__meta", domain_sending_tokens_path(domain), text: "None yet"
    assert_select ".trail__sentence", text: "#{users(:leo).name} added this domain"
  end

  test "the domain page says a record could not be looked up rather than never checked" do
    sign_in_as :leo
    domain = domains(:example)
    domain.update!(mx_error: "DNS timeout", dns_checked_at: Time.current)

    get domain_path(domain)

    assert_select ".settings__rows a[href=?] .row__meta", domain_dns_records_path(domain), text: /\AVerified · checked/
    assert_select ".trail__sentence", text: "DNS checked: DNS timeout"

    get domain_dns_records_path(domain)

    assert_select ".dns-item__error", text: "DNS timeout"
  end

  test "a domain's row ends with when its DNS was checked and a word for where it stands" do
    sign_in_as :leo
    verified = domains(:example)
    verified.update!(mx_status: :ok, dns_checked_at: 1.hour.ago)
    troubled = domains(:private)
    troubled.update!(mx_status: :ok, dmarc_status: :invalid, return_path_status: :missing, dns_checked_at: Time.current)
    unverified = domains(:unverified)
    unverified.update!(mx_status: :ok, dkim_status: :missing, dns_checked_at: Time.current)
    unchecked = Current.account.domains.create!(name: "new.example", creator: users(:leo))

    get domains_path

    assert_select "li##{dom_id verified}" do
      assert_select ".row__title", text: "example.com"
      assert_select ".row__meta", text: ""
      assert_select ".row__end time[data-reader-time-target=timeordate][datetime=?]", verified.dns_checked_at.to_i.to_s
      assert_select ".row__end .status.status--muted", text: "Verified"
    end
    assert_select "li##{dom_id troubled}" do
      assert_select ".row__meta", text: "DMARC record is not valid · Return-Path record is missing"
      assert_select ".row__end .status.status--warning", text: "DNS problems"
    end
    assert_select "li##{dom_id unverified}" do
      assert_select ".row__meta", text: "DKIM record is missing"
      assert_select ".row__end .status.status--warning", text: "Not verified"
    end
    assert_select "li##{dom_id unchecked}" do
      assert_select ".row__end time", count: 0
      assert_select ".row__end .status.status--muted", text: "Not checked"
    end
  end

  test "the unverified list names each record that needs work" do
    sign_in_as :leo
    domain = domains(:unverified)
    domain.update!(mx_status: :ok, dkim_status: :missing, dmarc_status: :invalid, dns_checked_at: Time.current)

    get domains_unverified_path
    assert_response :success
    assert_select "li##{dom_id domain} .row__meta", text: "DKIM record is missing · DMARC record is not valid"
    assert_select "li##{dom_id domain} .row__end .status.status--warning", text: "Not verified"
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
    assert_select "form[action=?] [data-turbo-confirm*=?]", domain_path(domain), "All its mail and its history go with it"

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
