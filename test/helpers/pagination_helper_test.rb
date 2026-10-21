require "test_helper"

class PaginationHelperTest < ActionView::TestCase
  test "next-page link does not honor an attacker-supplied script_name" do
    with_request_params controller: "events", action: "index", script_name: "/rails/active_storage/blobs/proxy/SIGNED/x.html%23" do
      assert_no_match %r{active_storage}, pagination_href(:events, 2)
      assert_match %r{\A/events\?}, pagination_href(:events, 2)
    end
  end

  test "next-page link does not honor an attacker-supplied original_script_name" do
    with_request_params controller: "events", action: "index", original_script_name: "/rails/active_storage/blobs/proxy/SIGNED/x.html%23" do
      assert_no_match %r{active_storage}, pagination_href(:events, 2)
      assert_match %r{\A/events\?}, pagination_href(:events, 2)
    end
  end

  test "next-page link does not honor other url_for control options" do
    with_request_params controller: "events", action: "index", host: "attacker.example", protocol: "https" do
      assert_no_match %r{attacker\.example}, pagination_href(:events, 2)
      assert_match %r{\A/events\?}, pagination_href(:events, 2)
    end
  end

  test "next-page link preserves ordinary filter params" do
    with_request_params controller: "searches", action: "show", q: "invoice" do
      assert_match %r{q=invoice}, pagination_href(:mailpieces, 2)
      assert_match %r{page=2}, pagination_href(:mailpieces, 2)
    end
  end

  private
    def with_request_params(**params)
      controller.params = ActionController::Parameters.new(params)
      yield
    end

    def pagination_href(namespace, page_number)
      Nokogiri::HTML::DocumentFragment.parse(pagination_link(namespace, page_number)).at_css("a")["href"]
    end
end
