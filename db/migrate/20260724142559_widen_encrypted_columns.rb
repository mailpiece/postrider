class WidenEncryptedColumns < ActiveRecord::Migration[8.2]
  def up
    # AR encryption stores a base64 envelope larger than the plaintext, so these
    # columns need room beyond their original 255 limit.
    change_column :webhooks, :signing_secret, :text
    change_column :identities, :email_address, :text
  end

  def down
    change_column :webhooks, :signing_secret, :string
    change_column :identities, :email_address, :string
  end
end
