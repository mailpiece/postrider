require "test_helper"

class Domains::SwitchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "show has a switch for receiving and one for sending, under Settings" do
    sign_in_as :leo

    get domain_switches_path(@domain)

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", edit_domain_path(@domain), text: "Settings"
    assert_select "form[action=?] input.switch__input[checked]", domain_receiving_path(@domain)
    assert_select "form[action=?] input.switch__input[checked]", domain_sending_path(@domain)
  end

  test "bulk mail has a switch that is off until it is turned on" do
    sign_in_as :leo

    get domain_switches_path(@domain)

    assert_select "form[action=?] input.switch__input:not([checked])", domain_bulk_path(@domain)
    assert_select ".row__title", text: "This is a bulk sending domain"
    assert_select ".row__meta", text: "Transactional: sent right away"
  end

  test "a switch that is on submits to turn it off" do
    sign_in_as :leo

    get domain_switches_path(@domain)

    assert_select "form[action=?] input[name=_method][value=delete]", domain_receiving_path(@domain)
  end

  test "a switch that is off submits to turn it on" do
    sign_in_as :leo
    @domain.update!(sending: false)

    get domain_switches_path(@domain)

    assert_select "form[action=?] input[name=_method]", domain_sending_path(@domain), count: 0
  end

  test "a member is refused" do
    sign_in_as :nonstaff

    get domain_switches_path(@domain)

    assert_response :forbidden
  end
end
