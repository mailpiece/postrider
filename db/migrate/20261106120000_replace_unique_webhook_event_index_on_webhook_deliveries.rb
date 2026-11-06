class ReplaceUniqueWebhookEventIndexOnWebhookDeliveries < ActiveRecord::Migration[8.2]
  def change
    remove_index :webhook_deliveries, [ :webhook_id, :event_id ], unique: true
    add_index :webhook_deliveries, :webhook_id
  end
end
