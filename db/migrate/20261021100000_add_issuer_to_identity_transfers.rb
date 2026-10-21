class AddIssuerToIdentityTransfers < ActiveRecord::Migration[8.2]
  def change
    add_column :identity_transfers, :issuer_id, :uuid
  end
end
