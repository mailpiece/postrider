class RemovePlansAndUsagesFromAccounts < ActiveRecord::Migration[8.2]
  def change
    remove_column :accounts, :plan_key, :string, limit: 255, default: "free_v1", null: false

    drop_table :account_usages, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.date :period_date, null: false
      t.bigint :request_count, default: 0, null: false
      t.timestamps
      t.index %i[ account_id period_date ], unique: true
    end
  end
end
