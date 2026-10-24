class AddReceivingAndSendingToDomains < ActiveRecord::Migration[8.2]
  def change
    add_column :domains, :receiving, :boolean, default: true, null: false
    add_column :domains, :sending, :boolean, default: true, null: false
  end
end
