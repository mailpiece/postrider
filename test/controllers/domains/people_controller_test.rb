require "test_helper"

class Domains::PeopleControllerTest < ActionDispatch::IntegrationTest
  test "shows the access list with current access checked" do
    sign_in_as :leo

    get domain_people_path(domains(:private))

    assert_response :success
    assert_select "input[name=?][value=?][checked=checked]", "user_ids[]", users(:leo).id.to_s
    assert_select "input[name=?][value=?]:not([checked])", "user_ids[]", users(:nonstaff).id.to_s
  end

  test "reflects whether the domain is open to everyone" do
    sign_in_as :leo

    get domain_people_path(domains(:example))
    assert_select "input#domain_all_access[checked=checked]"

    get domain_people_path(domains(:private))
    assert_select "input#domain_all_access:not([checked])"
  end
end
