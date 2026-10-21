class AddMailDomainCheckToRelayDnsChecks < ActiveRecord::Migration[8.2]
  def change
    add_column :relay_dns_checks, :mail_domain_status, :string, limit: 255
    add_column :relay_dns_checks, :mail_domain_error, :string, limit: 255
  end
end
