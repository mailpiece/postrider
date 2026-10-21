class AddCloudflareTokenToRelayCertificates < ActiveRecord::Migration[8.2]
  def change
    add_column :relay_certificates, :cloudflare_api_token, :text, limit: 65535
    add_column :relay_certificates, :cloudflare_zone, :string, limit: 255
  end
end
