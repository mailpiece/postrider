require "test_helper"

class Adminland::PausesControllerTest < ActionDispatch::IntegrationTest
  test "index lists the paused domains with the rejection that paused them" do
    pause = Pause.create!(recipient_domain: "gmail.com", smtp_output: "550 5.7.1 [203.0.113.7] is listed")
    sign_in_as :leo

    untenanted do
      get adminland_pauses_path

      assert_response :success
      assert_select ".row__title", text: "gmail.com"
      assert_select "code", text: "550 5.7.1 [203.0.113.7] is listed"
      assert_select "form[action=?] button", adminland_pause_path(pause), text: "Resume"
      assert_select ".breadcrumbs a[href=?]", adminland_settings_path, text: "Adminland"
    end
  end

  test "index says when nothing is paused" do
    sign_in_as :leo

    untenanted do
      get adminland_pauses_path

      assert_select ".blank-slate", text: /No paused domains/
    end
  end

  test "resume lifts the pause and traces it on the delivery that tripped it" do
    pause = Pause.create!(recipient_domain: "gmail.com", delivery: deliveries(:deferred))
    sign_in_as :leo

    untenanted do
      assert_difference -> { Pause.count } => -1, -> { deliveries(:deferred).events.where(action: "recipient_domain_resumed").count } => 1 do
        delete adminland_pause_path(pause)
      end

      assert_redirected_to adminland_pauses_path
    end
  end

  test "non-staff are forbidden" do
    pause = Pause.create!(recipient_domain: "gmail.com")
    sign_in_as :nonstaff

    untenanted do
      delete adminland_pause_path(pause)

      assert_response :forbidden
    end

    assert Pause.exists?(pause.id)
  end
end
