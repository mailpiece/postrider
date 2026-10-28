require "test_helper"

class PacingSlotTest < ActiveSupport::TestCase
  test "each reservation takes the next slot, a gap after the last" do
    freeze_time do
      assert_equal Time.current, PacingSlot.reserve("outlook", 30.seconds)
      assert_equal 30.seconds.from_now, PacingSlot.reserve("outlook", 30.seconds)
      assert_equal 60.seconds.from_now, PacingSlot.reserve("outlook", 30.seconds)
    end
  end

  test "a provider gone quiet starts again from now" do
    PacingSlot.create!(provider: "outlook", next_at: 1.hour.ago)

    freeze_time do
      assert_equal Time.current, PacingSlot.reserve("outlook", 30.seconds)
    end
  end

  test "providers keep their own slots" do
    freeze_time do
      PacingSlot.reserve("outlook", 30.seconds)

      assert_equal Time.current, PacingSlot.reserve("gmail", 2.seconds)
    end
  end
end
