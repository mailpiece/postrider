require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "signing in lands on mailpieces" do
    sign_in_as users(:leo)

    assert_selector "h1", text: "Mailpieces"
  end
end
