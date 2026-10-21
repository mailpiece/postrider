class AddAcmeDelegationCheckToRelayDnsChecks < ActiveRecord::Migration[8.2]
  def change
    add_column :relay_dns_checks, :acme_delegation_status, :string, limit: 255
    add_column :relay_dns_checks, :acme_delegation_error, :string, limit: 255
  end
end
