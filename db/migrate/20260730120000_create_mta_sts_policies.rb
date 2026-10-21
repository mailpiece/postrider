class CreateMtaStsPolicies < ActiveRecord::Migration[8.2]
  def change
    create_table :mta_sts_policies, id: :uuid do |t|
      t.string :domain, null: false, index: { unique: true }
      t.string :policy_id, null: false
      t.string :mode, null: false
      t.text :mx, null: false
      t.integer :max_age, null: false
      t.datetime :fetched_at, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end
  end
end
