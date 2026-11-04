require "test_helper"

class StatusHelperTest < ActionView::TestCase
  test "success statuses render a success pill" do
    assert_pill "delivered", semantic: "success", label: "Delivered"
    assert_pill "forwarded", semantic: "success", label: "Forwarded"
  end

  test "accepted mail, kept here and not passed on, renders a neutral pill" do
    assert_pill "accepted", semantic: "neutral", label: "Accepted"
    assert_equal "status--neutral", status_class("accepted")
  end

  test "error statuses render an error pill" do
    assert_pill "failed", semantic: "error", label: "Failed"
    assert_pill "bounced", semantic: "error", label: "Bounced"
    assert_pill "exhausted", semantic: "error", label: "Exhausted"
  end

  test "deferred renders a progress pill" do
    assert_pill "deferred", semantic: "progress", label: "Deferred"
  end

  test "processing renders a progress pill" do
    assert_pill "processing", semantic: "progress", label: "Processing"
  end

  test "pending and queued render a waiting pill" do
    assert_pill "pending", semantic: "waiting", label: "Pending"
    assert_pill "queued", semantic: "waiting", label: "Queued"
  end

  test "held renders a warning pill" do
    assert_pill "held", semantic: "warning", label: "Held"
    assert_equal "status--warning", status_class("held")
  end

  test "suppressed renders a muted pill" do
    assert_pill "suppressed", semantic: "muted", label: "Suppressed"
    assert_pill "withheld", semantic: "muted", label: "Withheld"
    assert_pill "discarded", semantic: "muted", label: "Discarded"
  end

  test "an unknown status falls back to neutral" do
    assert_pill "whatever", semantic: "neutral", label: "Whatever"
  end

  private
    def assert_pill(status, semantic:, label:)
      html = status_tag(status)
      assert_dom_equal %(<span class="status status--#{semantic}">#{label}</span>), html
    end
end
