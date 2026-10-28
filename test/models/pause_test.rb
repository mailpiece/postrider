require "test_helper"

class PauseTest < ActiveSupport::TestCase
  test "a provider is paused once, however it is spelled" do
    Pause.create!(provider: "Example.com ", recipient_domain: "example.com")

    assert_raises(ActiveRecord::RecordNotUnique) { Pause.create!(provider: "example.com", recipient_domain: "example.com") }
  end

  test "a provider is labelled by its name, any other by its domain" do
    assert_equal "Outlook.com", Pause.new(provider: "outlook").provider_label
    assert_equal "example.com", Pause.new(provider: "example.com").provider_label
  end

  test "resuming lifts the pause and tells the sender whose delivery tripped it" do
    pause = Pause.create!(provider: "example.com", recipient_domain: "example.com", delivery: deliveries(:deferred))

    assert_difference -> { deliveries(:deferred).events.where(action: "recipient_domain_resumed").count }, 1 do
      pause.resume
    end

    assert_not Pause.exists?(pause.id)
  end

  test "pauses that have ended resume, while those without an end wait for an operator" do
    ended = Pause.create!(provider: "outlook", recipient_domain: "hotmail.com", ends_at: 1.minute.ago)
    running = Pause.create!(provider: "yahoo", recipient_domain: "yahoo.com", ends_at: 1.minute.from_now)
    held = Pause.create!(provider: "example.com", recipient_domain: "example.com")

    Pause.resume_all_due

    assert_not Pause.exists?(ended.id)
    assert Pause.exists?(running.id)
    assert Pause.exists?(held.id)
  end

  test "a pause outlives the delivery that tripped it" do
    pause = Pause.create!(provider: "example.com", recipient_domain: "example.com", delivery: deliveries(:deferred))
    deliveries(:deferred).delete

    assert_no_difference -> { Event.count } do
      pause.reload.resume
    end

    assert_not Pause.exists?(pause.id)
  end
end
