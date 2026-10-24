# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_10_24_120000) do
  create_table "accesses", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "domain_id", null: false
    t.index ["account_id"], name: "index_accesses_on_account_id"
    t.index ["domain_id", "user_id"], name: "index_accesses_on_domain_id_and_user_id", unique: true
    t.index ["domain_id"], name: "index_accesses_on_domain_id"
    t.index ["user_id"], name: "index_accesses_on_user_id"
  end

  create_table "account_cancellations", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.datetime "created_at", null: false
    t.uuid "initiated_by_id", null: false
    t.index ["account_id"], name: "index_account_cancellations_on_account_id", unique: true
  end

  create_table "account_external_id_sequences", id: :uuid, force: :cascade do |t|
    t.bigint "value", default: 0, null: false
    t.index ["value"], name: "index_account_external_id_sequences_on_value", unique: true
  end

  create_table "account_join_codes", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "code", limit: 255, null: false
    t.bigint "usage_count", default: 0, null: false
    t.bigint "usage_limit", default: 10, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "code"], name: "index_account_join_codes_on_account_id_and_code", unique: true
  end

  create_table "accounts", id: :uuid, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.bigint "external_account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "contacts_count", default: 0, null: false
    t.index ["external_account_id"], name: "index_accounts_on_external_account_id", unique: true
  end

  create_table "action_pack_passkeys", id: :uuid, force: :cascade do |t|
    t.uuid "holder_id", null: false
    t.string "holder_type", limit: 255, null: false
    t.string "credential_id", limit: 255, null: false
    t.binary "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "name", limit: 255
    t.text "transports", limit: 65535
    t.string "aaguid", limit: 255
    t.boolean "backed_up"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["credential_id"], name: "index_action_pack_passkeys_on_credential_id", unique: true
    t.index ["holder_type", "holder_id"], name: "index_action_pack_passkeys_on_holder_type_and_holder_id"
  end

  create_table "active_storage_attachments", id: :uuid, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "record_type", limit: 255, null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, force: :cascade do |t|
    t.string "key", limit: 255, null: false
    t.string "filename", limit: 255, null: false
    t.string "content_type", limit: 255
    t.text "metadata", limit: 65535
    t.string "service_name", limit: 255, null: false
    t.bigint "byte_size", null: false
    t.string "checksum", limit: 255
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", limit: 255, null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "contacts", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "domain_id", null: false
    t.bigint "number", null: false
    t.string "email", limit: 255, null: false
    t.string "name", limit: 255
    t.string "decision", limit: 255, default: "denied", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "number"], name: "index_contacts_on_account_id_and_number", unique: true
    t.index ["domain_id", "decision"], name: "index_contacts_on_domain_id_and_decision"
    t.index ["domain_id", "email"], name: "index_contacts_on_domain_id_and_email", unique: true
  end

  create_table "deliveries", id: :uuid, force: :cascade do |t|
    t.uuid "message_id", null: false
    t.string "rcpt_to", limit: 255
    t.string "status", limit: 255, default: "queued", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id", null: false
    t.string "subject", limit: 255, default: "", null: false
    t.string "mail_from", limit: 255
    t.uuid "domain_id", null: false
    t.index ["account_id", "created_at"], name: "index_deliveries_on_account_id_and_created_at"
    t.index ["account_id", "status"], name: "index_deliveries_on_account_id_and_status"
    t.index ["domain_id"], name: "index_deliveries_on_domain_id"
    t.index ["message_id"], name: "index_deliveries_on_message_id"
    t.index ["status"], name: "index_deliveries_on_status"
  end

  create_table "delivery_attempts", id: :uuid, force: :cascade do |t|
    t.uuid "delivery_id", null: false
    t.string "code", limit: 255
    t.text "output", limit: 65535
    t.string "mx_host", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "transcript", limit: 65535
    t.index ["delivery_id"], name: "index_delivery_attempts_on_delivery_id"
  end

  create_table "domains", id: :uuid, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "dkim_selector", limit: 255, null: false
    t.text "dkim_private_key", limit: 65535, null: false
    t.string "dkim_status", limit: 255
    t.string "dkim_error", limit: 255
    t.string "mx_status", limit: 255
    t.string "mx_error", limit: 255
    t.datetime "dns_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id", null: false
    t.string "catch_all_policy", limit: 255, default: "disabled", null: false
    t.string "dmarc_status", limit: 255
    t.string "dmarc_error", limit: 255
    t.string "return_path_status", limit: 255
    t.string "return_path_error", limit: 255
    t.boolean "all_access", default: false, null: false
    t.uuid "creator_id", null: false
    t.integer "suppressions_count", default: 0, null: false
    t.text "blocked_phrases", limit: 65535
    t.text "allowed_ips", limit: 65535
    t.boolean "receiving", default: true, null: false
    t.boolean "sending", default: true, null: false
    t.index ["account_id"], name: "index_domains_on_account_id"
    t.index ["creator_id"], name: "index_domains_on_creator_id"
    t.index ["name"], name: "index_domains_on_name", unique: true
  end

  create_table "events", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "action", limit: 255, null: false
    t.string "eventable_type", limit: 255, null: false
    t.uuid "eventable_id", null: false
    t.json "particulars", default: -> { "json_object()" }
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "domain_id", null: false
    t.index ["account_id", "action"], name: "index_events_on_account_id_and_action"
    t.index ["account_id", "created_at"], name: "index_events_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_events_on_account_id"
    t.index ["domain_id", "action", "created_at"], name: "index_events_on_domain_id_and_action_and_created_at"
    t.index ["domain_id"], name: "index_events_on_domain_id"
    t.index ["eventable_type", "eventable_id"], name: "index_events_on_eventable_type_and_eventable_id"
  end

  create_table "idempotent_requests", id: :uuid, force: :cascade do |t|
    t.uuid "sending_token_id", null: false
    t.string "key", limit: 255, null: false
    t.uuid "message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_idempotent_requests_on_message_id"
    t.index ["sending_token_id", "key"], name: "index_idempotent_requests_on_sending_token_id_and_key", unique: true
  end

  create_table "identities", id: :uuid, force: :cascade do |t|
    t.text "email_address", limit: 255, null: false
    t.boolean "staff", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_identities_on_email_address", unique: true
  end

  create_table "identity_access_tokens", id: :uuid, force: :cascade do |t|
    t.uuid "identity_id", null: false
    t.string "token_digest", limit: 255, null: false
    t.string "permission", limit: 255
    t.text "description", limit: 65535
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_identity_access_tokens_on_identity_id"
    t.index ["token_digest"], name: "index_identity_access_tokens_on_token_digest", unique: true
  end

  create_table "identity_transfers", id: :uuid, force: :cascade do |t|
    t.uuid "identity_id", null: false
    t.string "token", limit: 255, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "issuer_id"
    t.index ["identity_id"], name: "index_identity_transfers_on_identity_id"
    t.index ["token"], name: "index_identity_transfers_on_token", unique: true
  end

  create_table "inbound_emails", id: :uuid, force: :cascade do |t|
    t.string "mail_from", limit: 255
    t.string "rcpt_to", limit: 255
    t.string "status", limit: 255, default: "pending", null: false
    t.datetime "forwarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id", null: false
    t.string "digest", limit: 64
    t.string "spf", limit: 255
    t.string "dkim", limit: 255
    t.string "dmarc", limit: 255
    t.string "subject", limit: 255, default: "", null: false
    t.uuid "domain_id", null: false
    t.string "arc", limit: 255
    t.string "arc_sealer", limit: 255
    t.string "dmarc_policy", limit: 255
    t.boolean "from_aligned", default: false, null: false
    t.uuid "contact_id"
    t.text "authentication_results", limit: 65535
    t.string "iprev", limit: 255
    t.string "remote_host", limit: 255
    t.index ["account_id", "created_at"], name: "index_inbound_emails_on_account_id_and_created_at"
    t.index ["account_id", "digest", "rcpt_to"], name: "index_inbound_emails_on_account_id_and_digest_and_rcpt_to", unique: true
    t.index ["account_id"], name: "index_inbound_emails_on_account_id"
    t.index ["contact_id"], name: "index_inbound_emails_on_contact_id"
    t.index ["domain_id"], name: "index_inbound_emails_on_domain_id"
    t.index ["status"], name: "index_inbound_emails_on_status"
  end

  create_table "incinerations", id: :uuid, force: :cascade do |t|
    t.string "incinerable_type", limit: 255, null: false
    t.uuid "incinerable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incinerable_type", "incinerable_id"], name: "index_incinerations_on_incinerable_type_and_incinerable_id", unique: true
  end

  create_table "mailboxes", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "domain_id", null: false
    t.string "local_part", limit: 255, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "forward_to", limit: 255
    t.datetime "forward_confirmed_at"
    t.index ["account_id"], name: "index_mailboxes_on_account_id"
    t.index ["domain_id", "local_part"], name: "index_mailboxes_on_domain_id_and_local_part", unique: true
    t.index ["domain_id"], name: "index_mailboxes_on_domain_id"
  end

  create_table "mailpieces", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "postable_type", limit: 255, null: false
    t.uuid "postable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "domain_id", null: false
    t.index ["account_id", "created_at"], name: "index_mailpieces_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_mailpieces_on_account_id"
    t.index ["domain_id", "created_at"], name: "index_mailpieces_on_domain_id_and_created_at"
    t.index ["postable_type", "postable_id"], name: "index_mailpieces_on_postable", unique: true
  end

  create_table "messages", id: :uuid, force: :cascade do |t|
    t.string "mail_from", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id", null: false
    t.string "envelope_from", limit: 255
    t.text "tags", limit: 65535
    t.string "subject", limit: 255, default: "", null: false
    t.uuid "domain_id", null: false
    t.string "mail_message_id", limit: 255
    t.text "metadata", limit: 65535
    t.string "origin", limit: 255, default: "submitted", null: false
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["domain_id"], name: "index_messages_on_domain_id"
  end

  create_table "mta_sts_policies", id: :uuid, force: :cascade do |t|
    t.string "domain", limit: 255, null: false
    t.string "policy_id", limit: 255, null: false
    t.string "mode", limit: 255, null: false
    t.text "mx", limit: 65535, null: false
    t.integer "max_age", null: false
    t.datetime "fetched_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_mta_sts_policies_on_domain", unique: true
  end

  create_table "pauses", id: :uuid, force: :cascade do |t|
    t.string "recipient_domain", limit: 255, null: false
    t.text "smtp_output", limit: 65535
    t.uuid "delivery_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_pauses_on_delivery_id"
    t.index ["recipient_domain"], name: "index_pauses_on_recipient_domain", unique: true
  end

  create_table "relay_certificates", id: :uuid, force: :cascade do |t|
    t.text "pem", limit: 65535
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "acme_account_key", limit: 65535
    t.text "renewal_error", limit: 65535
    t.json "acme_challenge_records"
  end

  create_table "relay_dns_check_addresses", id: :uuid, force: :cascade do |t|
    t.uuid "relay_dns_check_id", null: false
    t.string "address", limit: 255, null: false
    t.string "ptr_hostname", limit: 255
    t.string "expected_ptr_hostname", limit: 255, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["relay_dns_check_id"], name: "index_relay_dns_check_addresses_on_relay_dns_check_id"
  end

  create_table "relay_dns_checks", id: :uuid, force: :cascade do |t|
    t.integer "singleton_guard", default: 0, null: false
    t.string "address_status", limit: 255
    t.string "address_error", limit: 255
    t.string "ptr_status", limit: 255
    t.string "ptr_error", limit: 255
    t.string "spf_status", limit: 255
    t.string "spf_error", limit: 255
    t.datetime "dns_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "submission_address_status", limit: 255
    t.string "submission_address_error", limit: 255
    t.string "mail_domain_status", limit: 255
    t.string "mail_domain_error", limit: 255
    t.string "sealing_key_status", limit: 255
    t.string "sealing_key_error", limit: 255
    t.string "acme_delegation_status", limit: 255
    t.string "acme_delegation_error", limit: 255
    t.index ["singleton_guard"], name: "index_relay_dns_checks_on_singleton_guard", unique: true
  end

  create_table "relay_sealing_keys", id: :uuid, force: :cascade do |t|
    t.integer "singleton_guard", default: 0, null: false
    t.text "private_key", limit: 65535
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["singleton_guard"], name: "index_relay_sealing_keys_on_singleton_guard", unique: true
  end

  create_table "sending_tokens", id: :uuid, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "token_digest", limit: 255, null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id", null: false
    t.uuid "domain_id", null: false
    t.index ["account_id"], name: "index_sending_tokens_on_account_id"
    t.index ["domain_id"], name: "index_sending_tokens_on_domain_id"
    t.index ["token_digest"], name: "index_sending_tokens_on_token_digest", unique: true
  end

  create_table "sessions", id: :uuid, force: :cascade do |t|
    t.uuid "identity_id", null: false
    t.string "ip_address", limit: 255
    t.string "user_agent", limit: 4096
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "sudo_at"
    t.index ["identity_id"], name: "index_sessions_on_identity_id"
  end

  create_table "settings", id: :uuid, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id", null: false
    t.string "bounce_address", limit: 255
    t.index ["account_id"], name: "index_settings_on_account_id", unique: true
  end

  create_table "suppressions", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "address", limit: 255, null: false
    t.string "reason", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "domain_id", null: false
    t.datetime "expires_at"
    t.index ["account_id"], name: "index_suppressions_on_account_id"
    t.index ["domain_id", "address"], name: "index_suppressions_on_domain_id_and_address", unique: true
  end

  create_table "user_settings", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "user_id", null: false
    t.string "timezone_name", limit: 255
    t.integer "bundle_email_frequency", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_user_settings_on_account_id"
    t.index ["user_id", "bundle_email_frequency"], name: "index_user_settings_on_user_id_and_bundle_email_frequency"
    t.index ["user_id"], name: "index_user_settings_on_user_id"
  end

  create_table "users", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "identity_id"
    t.string "name", limit: 255, null: false
    t.string "role", limit: 255, default: "member", null: false
    t.boolean "active", default: true, null: false
    t.datetime "verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "identity_id"], name: "index_users_on_account_id_and_identity_id", unique: true
    t.index ["account_id", "role"], name: "index_users_on_account_id_and_role"
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["identity_id"], name: "index_users_on_identity_id"
  end

  create_table "webhook_delinquency_trackers", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "webhook_id", null: false
    t.integer "consecutive_failures_count", default: 0
    t.datetime "first_failure_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_webhook_delinquency_trackers_on_account_id"
    t.index ["webhook_id"], name: "index_webhook_delinquency_trackers_on_webhook_id"
  end

  create_table "webhook_deliveries", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "webhook_id", null: false
    t.uuid "event_id", null: false
    t.text "request", limit: 65535
    t.text "response", limit: 65535
    t.string "state", limit: 255, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_webhook_deliveries_on_account_id"
    t.index ["created_at"], name: "index_webhook_deliveries_on_created_at"
    t.index ["event_id"], name: "index_webhook_deliveries_on_event_id"
    t.index ["webhook_id", "event_id"], name: "index_webhook_deliveries_on_webhook_id_and_event_id", unique: true
  end

  create_table "webhooks", id: :uuid, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.boolean "active", default: true, null: false
    t.string "name", limit: 255
    t.text "signing_secret", limit: 255, null: false
    t.text "subscribed_actions", limit: 65535
    t.text "url", limit: 65535, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "domain_id", null: false
    t.index ["account_id"], name: "index_webhooks_on_account_id"
    t.index ["domain_id", "subscribed_actions"], name: "index_webhooks_on_domain_id_and_subscribed_actions"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "relay_dns_check_addresses", "relay_dns_checks"
end
