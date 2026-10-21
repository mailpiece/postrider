class RemoveCloudflareFromRelayCertificates < ActiveRecord::Migration[8.2]
  def change
    remove_column :relay_certificates, :cloudflare_api_token, :text, limit: 65535
    remove_column :relay_certificates, :cloudflare_zone, :string, limit: 255
    remove_column :relay_certificates, :acme_challenge_token, :string, limit: 255
    remove_column :relay_certificates, :acme_challenge_content, :string, limit: 255
  end
end
