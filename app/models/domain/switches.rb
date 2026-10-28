module Domain::Switches
  extend ActiveSupport::Concern

  def turn_receiving_on
    transaction do
      update! receiving: true
      track_event "receiving_turned_on" if saved_change_to_receiving?
    end
  end

  def turn_receiving_off
    transaction do
      update! receiving: false
      track_event "receiving_turned_off" if saved_change_to_receiving?
    end
  end

  def turn_sending_on
    transaction do
      update! sending: true
      track_event "sending_turned_on" if saved_change_to_sending?
    end
  end

  def turn_sending_off
    transaction do
      update! sending: false
      track_event "sending_turned_off" if saved_change_to_sending?
    end
  end

  def turn_bulk_on
    transaction do
      update! bulk: true
      track_event "bulk_turned_on" if saved_change_to_bulk?
    end
  end

  def turn_bulk_off
    transaction do
      update! bulk: false
      track_event "bulk_turned_off" if saved_change_to_bulk?
    end
  end
end
