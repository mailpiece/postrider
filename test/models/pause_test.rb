require "test_helper"

class PauseTest < ActiveSupport::TestCase
  test "a recipient domain is paused once, however it is spelled" do
    Pause.create!(recipient_domain: "Gmail.com ")

    assert_raises(ActiveRecord::RecordNotUnique) { Pause.create!(recipient_domain: "gmail.com") }
  end

  test "resuming lifts the pause and tells the sender whose delivery tripped it" do
    pause = Pause.create!(recipient_domain: "example.com", delivery: deliveries(:deferred))

    assert_difference -> { deliveries(:deferred).events.where(action: "recipient_domain_resumed").count }, 1 do
      pause.resume
    end

    assert_not Pause.exists?(pause.id)
  end

  test "a pause outlives the delivery that tripped it" do
    pause = Pause.create!(recipient_domain: "example.com", delivery: deliveries(:deferred))
    deliveries(:deferred).delete

    assert_no_difference -> { Event.count } do
      pause.reload.resume
    end

    assert_not Pause.exists?(pause.id)
  end
end
