require "test_helper"

class Domains::PeopleControllerTest < ActionDispatch::IntegrationTest
  test "shows the access list with current access checked" do
    sign_in_as :leo

    get domain_people_path(domains(:private))

    assert_response :success
    assert_select "h2", text: "Who can use this domain"
    assert_select "input[name=?][value=?][checked=checked]", "user_ids[]", users(:leo).id.to_s
    assert_select "input[name=?][value=?]:not([checked])", "user_ids[]", users(:nonstaff).id.to_s
  end

  test "marks the signed-in user's own switch, so removing yourself warns first" do
    sign_in_as :leo

    get domain_people_path(domains(:private))

    assert_select "input[value=?][data-accesses-form-target=?]", users(:leo).id.to_s, "meCheckbox"
    assert_select "input[value=?][data-accesses-form-target=?]", users(:nonstaff).id.to_s, "meCheckbox", count: 0
  end

  test "reflects an open domain as toggled, so the switches read as locked on" do
    sign_in_as :leo

    get domain_people_path(domains(:example))
    assert_select "[data-controller~=toggle-class].toggler--toggled"
    assert_select "input#domain_all_access[checked=checked]"

    get domain_people_path(domains(:private))
    assert_select "[data-controller~=toggle-class].toggler--toggled", count: 0
    assert_select "input#domain_all_access:not([checked])"
  end
end
