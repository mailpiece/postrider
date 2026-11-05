class AddRetryTimesToDeliveries < ActiveRecord::Migration[8.2]
  def change
    add_column :deliveries, :first_failed_at, :datetime
    add_column :deliveries, :next_retry_at, :datetime
  end
end
