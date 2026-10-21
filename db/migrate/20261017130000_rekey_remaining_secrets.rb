# Rewrites what code from before StoreEmailAddressesPlainAndRekeySecrets kept
# writing during the overlap, as that migration did: an email address it
# still encrypted and a secret it wrote under the old keys, which no later
# write has touched. Once the keys leave the environment such a row could not
# be read, so this runs before they do.
#
# The old keys came from the three ACTIVE_RECORD_ENCRYPTION variables, which
# the initializer still reads as previous keys: they must be in ENV for this
# one run, or a value they encrypted stops the migration before it writes
# anything, naming the column but never the value.
#
# SQLite cannot decrypt, so this runs in Ruby, a batch at a time, outside one
# long transaction. update_columns and encrypt leave updated_at alone.
#
# Rerunnable: a plain email address and a secret the current keys already
# decrypt are left alone, and a fresh install has no rows to touch. Its down
# is a no-op, so `db:migrate:redo:primary VERSION=20261017130000` runs it again.
class RekeyRemainingSecrets < ActiveRecord::Migration[8.2]
  disable_ddl_transaction!

  BATCH_SIZE = 500

  class Identity < ActiveRecord::Base
    self.table_name = "identities"
  end

  class EncryptedIdentity < ActiveRecord::Base
    self.table_name = "identities"
    encrypts :email_address, deterministic: true
  end

  class Webhook < ActiveRecord::Base
    self.table_name = "webhooks"
    encrypts :signing_secret
  end

  class Certificate < ActiveRecord::Base
    self.table_name = "relay_certificates"
    encrypts :pem, :acme_account_key
  end

  class SealingKey < ActiveRecord::Base
    self.table_name = "relay_sealing_keys"
    encrypts :private_key
  end

  class Domain < ActiveRecord::Base
    self.table_name = "domains"
    encrypts :dkim_private_key
  end

  def up
    refuse_undecryptable
    store_email_addresses_plain
    [ Webhook, Certificate, SealingKey, Domain ].each { |model| rekey model }
  end

  def down
    # The rows hold what they held, under the current keys: nothing to undo.
  end

  private
    # A value under keys neither current nor previous would stop the rewrite
    # partway through. Stop before writing anything instead, naming the column
    # but never the value.
    def refuse_undecryptable
      [ EncryptedIdentity, Webhook, Certificate, SealingKey, Domain ].each do |model|
        model.in_batches(of: BATCH_SIZE) do |batch|
          batch.select(:id, *model.encrypted_attributes).each do |row|
            model.encrypted_attributes.each do |column|
              decrypt row, column if encrypted?(row.read_attribute_before_type_cast(column))
            end
          end
        end
      end
    end

    def store_email_addresses_plain
      Identity.in_batches(of: BATCH_SIZE) do |batch|
        batch.each do |identity|
          if encrypted?(identity.email_address)
            identity.update_columns email_address: EncryptedIdentity.find(identity.id).email_address
          end
        end
      end
    end

    def rekey(model)
      model.in_batches(of: BATCH_SIZE) do |batch|
        batch.each do |row|
          row.encrypt if model.encrypted_attributes.any? { |column| under_old_keys?(row, column) }
        end
      end
    end

    def under_old_keys?(row, column)
      ciphertext = row.read_attribute_before_type_cast(column)
      encrypted?(ciphertext) && !current_keys_decrypt?(ciphertext)
    end

    def encrypted?(value)
      ActiveRecord::Encryption.encryptor.encrypted?(value)
    end

    def current_keys_decrypt?(ciphertext)
      ActiveRecord::Encryption.encryptor.decrypt(ciphertext)
      true
    rescue ActiveRecord::Encryption::Errors::Decryption
      false
    end

    def decrypt(row, column)
      row[column]
    rescue ActiveRecord::Encryption::Errors::Decryption
      raise "#{row.class.table_name}.#{column} holds a value the keys cannot decrypt. Set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, " \
        "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY and ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT for this one deploy " \
        "so the migration can re-encrypt it."
    end
end
