class AddProviderToPauses < ActiveRecord::Migration[8.2]
  def change
    up_only { execute "DELETE FROM pauses" }

    add_column :pauses, :provider, :string, limit: 255, null: false

    remove_index :pauses, :recipient_domain, unique: true
    add_index :pauses, :provider, unique: true
  end
end
