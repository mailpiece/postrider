class CreatePacingSlots < ActiveRecord::Migration[8.2]
  def change
    create_table :pacing_slots, id: :uuid do |t|
      t.string :provider, limit: 255, null: false
      t.datetime :next_at, null: false

      t.timestamps

      t.index :provider, unique: true
    end
  end
end
