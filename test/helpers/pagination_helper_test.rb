require "test_helper"

# pagination_link builds the "next page" URL from the request. url_for reads
# reserved keys such as `script_name`, `host`, `only_path` and `use_route` as
# URL-generation options, and any other key as a possible path segment, so a query
# must never reach it as options: only as the link's own query string.
class PaginationHelperTest < ActionView::TestCase
  OWN_PATH = "/domains/the-domain/webhooks"
  OWN_ROUTE = { controller: "webhooks", action: "index", domain_id: "the-domain" }

  {
    script_name: "/elsewhere",
    original_script_name: "/elsewhere",
    relative_url_root: "/elsewhere",
    host: "elsewhere.example",
    protocol: "ftp",
    port: "8080",
    subdomain: "elsewhere",
    domain: "elsewhere.example",
    tld_length: "0",
    only_path: "false",
    trailing_slash: "true",
    anchor: "elsewhere",
    user: "someone",
    password: "secret",
    use_route: "root",
    path_params: { format: "xml" },
    params: { elsewhere: "true" },
    _recall: { controller: "mailpieces", action: "index" },
    format: "xml",
    controller: "mailpieces",
    action: "index",
    id: "elsewhere",
    domain_id: "elsewhere"
  }.each do |option, value|
    test "next-page link keeps to its own route when the query names #{option}" do
      with_request query: { option => value } do
        assert_equal OWN_PATH, pagination_uri.path
        assert_nil pagination_uri.host
        assert_nil pagination_uri.fragment
        assert_equal "2", pagination_query["page"]
      end
    end
  end

  test "next-page link keeps the query" do
    with_request query: { tag: "urgent", terms: [ "one", "two" ], nested: { key: "value" } } do
      assert_equal OWN_PATH, pagination_uri.path
      assert_equal "urgent", pagination_query["tag"]
      assert_equal [ "one", "two" ], pagination_query["terms"]
      assert_equal({ "key" => "value" }, pagination_query["nested"])
    end
  end

  test "next-page link replaces the query's page" do
    with_request query: { page: "7" } do
      assert_equal "2", pagination_query["page"]
    end
  end

  test "next-page link leaves out form params" do
    with_request form: { authenticity_token: "secret" } do
      assert_nil pagination_query["authenticity_token"]
    end
  end

  private
    def with_request(query: {}, form: {})
      request.path_parameters = OWN_ROUTE
      request.set_header "QUERY_STRING", query.to_query
      request.request_parameters = form
      controller.params = ActionController::Parameters.new(query.merge(form).merge(OWN_ROUTE))
      yield
    end

    def pagination_uri
      URI(Nokogiri::HTML::DocumentFragment.parse(pagination_link(:webhooks, 2)).at_css("a")["href"])
    end

    def pagination_query
      Rack::Utils.parse_nested_query(pagination_uri.query)
    end
end
