class AddAllowedIpsToDomains < ActiveRecord::Migration[8.2]
  def change
    add_column :domains, :allowed_ips, :text, limit: 65535
  end
end
