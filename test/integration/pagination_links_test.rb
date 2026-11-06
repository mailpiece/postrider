require "test_helper"

# A next-page link is built from the request's query string, so what a query says
# must only ever end up back in a query string. These tests render every page that
# paginates with url_for, through real routing, because url_for reads its recalled
# route from the request and a helper test can't vouch for that.
class PaginationLinksTest < ActionDispatch::IntegrationTest
  QUERIES_NAMING_URL_FOR_OPTIONS = [
    { use_route: "root" },
    { use_route: "mailpiece", id: "1" },
    { path_params: { format: "xml", domain_id: "elsewhere" } }
  ]

  setup do
    @domain = domains(:example)
    sign_in_as :leo
  end

  {
    "held" => :mailpieces_held_path, "failed" => :mailpieces_failed_path, "withheld" => :mailpieces_withheld_path,
    "deferred" => :mailpieces_deferred_path, "queued" => :mailpieces_queued_path, "discarded" => :mailpieces_discarded_path,
    "domains" => :domains_path, "not verified" => :domains_unverified_path,
    "contacts" => :contacts_path, "denied" => :contacts_denied_path,
    "suppressions" => :suppressions_path, "users" => :users_path, "events" => :events_path
  }.each do |name, page|
    test "#{name} page's next-page link stays on its own route" do
      paginate_every_page

      [ {}, *QUERIES_NAMING_URL_FOR_OPTIONS ].each do |query|
        assert_next_page_stays_on send(page), **query
      end
    end
  end

  { "sending tokens" => :domain_sending_tokens_path, "webhooks" => :domain_webhooks_path, "mailboxes" => :domain_mailboxes_path }.each do |name, page|
    test "domain #{name} page's next-page link stays on its own route" do
      paginate_every_page

      [ {}, *QUERIES_NAMING_URL_FOR_OPTIONS ].each do |query|
        assert_next_page_stays_on send(page, @domain), **query
      end
    end
  end

  test "contact page's next-page link stays on its own route" do
    paginate_every_page

    [ {}, *QUERIES_NAMING_URL_FOR_OPTIONS ].each do |query|
      assert_next_page_stays_on contact_path(contacts(:approved)), **query
    end
  end

  # The mail log answers at the root too, and url_for names the root for it.
  test "mail log's next-page link stays on its own route" do
    paginate

    [ {}, *QUERIES_NAMING_URL_FOR_OPTIONS ].each do |query|
      assert_next_page_stays_on root_path, **query
    end
  end

  test "search page's next-page link stays on its own route and keeps the search" do
    paginate subject: "needle"

    [ {}, *QUERIES_NAMING_URL_FOR_OPTIONS ].each do |query|
      assert_next_page_stays_on search_path, q: "needle", **query
      assert_equal "needle", next_page_query["q"]
    end
  end

  test "the next-page link answers with the next page" do
    paginate

    get root_path, params: { use_route: "root" }
    get next_page_href

    assert_response :success
    assert_select "a.pagination-link", count: 0
  end

  private
    def paginate(subject: "Paginated")
      16.times do |index|
        create_inbound_email(raw: "Subject: #{subject} #{index}\r\n\r\nBody")
      end
    end

    # These pages list records the fixtures hold too few of to run past one page.
    def paginate_every_page
      GearedPagination::Page.any_instance.stubs(:used?).returns(true)
      GearedPagination::Page.any_instance.stubs(:before_last?).returns(true)
    end

    def assert_next_page_stays_on(path, **query)
      get path, params: query
      assert_response :success

      assert_equal path, URI(next_page_href).path
      assert_equal "2", next_page_query["page"]
    end

    def next_page_href
      css_select("a.pagination-link").first&.[]("href") || flunk("expected a next-page link")
    end

    def next_page_query
      Rack::Utils.parse_nested_query(URI(next_page_href).query)
    end
end
