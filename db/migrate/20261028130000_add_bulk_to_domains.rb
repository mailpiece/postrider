class AddBulkToDomains < ActiveRecord::Migration[8.2]
  def change
    add_column :domains, :bulk, :boolean, default: false, null: false
  end
end
