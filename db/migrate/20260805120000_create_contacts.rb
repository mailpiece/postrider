class CreateContacts < ActiveRecord::Migration[8.2]
  def change
    create_table :contacts, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :domain_id, null: false
      t.bigint :number, null: false
      t.string :email, limit: 255, null: false
      t.string :name, limit: 255
      t.string :decision, limit: 255, default: "denied", null: false
      t.timestamps

      t.index [ :account_id, :number ], unique: true
      t.index [ :domain_id, :email ], unique: true
      t.index [ :domain_id, :decision ]
    end

    add_column :accounts, :contacts_count, :bigint, default: 0, null: false

    add_column :inbound_emails, :from_aligned, :boolean, default: false, null: false
    add_column :inbound_emails, :contact_id, :uuid
    add_index :inbound_emails, :contact_id
  end
end
