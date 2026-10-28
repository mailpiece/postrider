require "test_helper"

class Domain::SwitchesTest < ActiveSupport::TestCase
  setup do
    @domain = domains(:example)
  end

  test "turning receiving off records it" do
    assert_difference -> { @domain.events.where(action: "domain_receiving_turned_off").count }, 1 do
      @domain.turn_receiving_off
    end
  end

  test "turning receiving on records it" do
    @domain.update!(receiving: false)

    assert_difference -> { @domain.events.where(action: "domain_receiving_turned_on").count }, 1 do
      @domain.turn_receiving_on
    end
  end

  test "turning sending off records it" do
    assert_difference -> { @domain.events.where(action: "domain_sending_turned_off").count }, 1 do
      @domain.turn_sending_off
    end
  end

  test "turning sending on records it" do
    @domain.update!(sending: false)

    assert_difference -> { @domain.events.where(action: "domain_sending_turned_on").count }, 1 do
      @domain.turn_sending_on
    end
  end

  test "turning bulk mail on records it" do
    assert_difference -> { @domain.events.where(action: "domain_bulk_turned_on").count }, 1 do
      @domain.turn_bulk_on
    end
  end

  test "turning bulk mail off records it" do
    @domain.update!(bulk: true)

    assert_difference -> { @domain.events.where(action: "domain_bulk_turned_off").count }, 1 do
      @domain.turn_bulk_off
    end
  end

  test "turning on what is already on records nothing" do
    assert_no_difference -> { @domain.events.count } do
      @domain.turn_receiving_on
    end
  end

  test "with receiving off a mailbox is refused" do
    @domain.turn_receiving_off

    assert_not @domain.accepts?("inbox@example.com")
  end

  test "with receiving off dmarc-reports is refused" do
    @domain.turn_receiving_off

    assert_not @domain.accepts?("dmarc-reports@example.com")
  end

  test "with receiving off the catch-all is refused" do
    @domain.update!(catch_all_policy: "forward")
    @domain.turn_receiving_off

    assert_not @domain.accepts?("nobody@example.com")
  end

  test "with receiving off the bounce address is still accepted" do
    @domain.account.setting.update!(bounce_address: "bounces@example.com")
    @domain.turn_receiving_off

    assert @domain.accepts?("bounces@example.com")
  end

  test "with receiving off a VERP return path is still accepted" do
    @domain.update!(dmarc_status: :ok, return_path_status: :ok)
    @domain.turn_receiving_off

    assert Delivery::ReturnPath.address?(Delivery::ReturnPath.new(deliveries(:queued)).address)
  end
end
