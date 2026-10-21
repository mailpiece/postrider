require "application_system_test_case"

class EmailBodyTest < ApplicationSystemTestCase
  test "an html-only body is never rendered, so its scripts never run" do
    raw = <<~EOM
      Subject: Hostile
      Content-Type: text/html

      <p>hello</p>
      <script>window.postriderXss = true</script>
      <img src="x" onerror="window.postriderXss = true">
    EOM
    create_inbound_email(raw: raw)
    sign_in_as users(:leo)

    visit search_path(q: "Hostile")
    click_on "Hostile"

    assert_link "View the original source"
    assert_no_selector "iframe"
    assert_nil evaluate_script("window.postriderXss")
  end
end
