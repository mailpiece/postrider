class RemovePreviewFromMail < ActiveRecord::Migration[8.2]
  def change
    remove_column :deliveries, :preview, :string, limit: 255, default: "", null: false
    remove_column :inbound_emails, :preview, :string, limit: 255, default: "", null: false
    remove_column :messages, :preview, :string, limit: 255, default: "", null: false
  end
end
