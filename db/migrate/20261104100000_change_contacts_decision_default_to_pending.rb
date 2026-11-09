class ChangeContactsDecisionDefaultToPending < ActiveRecord::Migration[8.2]
  def change
    change_column_default :contacts, :decision, from: "denied", to: "pending"
  end
end
