class AddSealingKeyCheckToRelayDnsChecks < ActiveRecord::Migration[8.2]
  def change
    add_column :relay_dns_checks, :sealing_key_status, :string, limit: 255
    add_column :relay_dns_checks, :sealing_key_error, :string, limit: 255
  end
end
