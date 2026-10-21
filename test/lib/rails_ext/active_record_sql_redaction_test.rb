require "test_helper"

class ActiveRecordSqlRedactionTest < ActiveSupport::TestCase
  # Made-up values, distinctive enough that finding one in a log can only mean it leaked.
  JOIN_CODE = "Zfak-eJoi-nCod"
  TRANSFER_TOKEN = "madeUpTransferToken00000"
  OTHER_TRANSFER_TOKEN = "madeUpTransferToken00001"
  SECRET = "madeUpSigningSecret00000"
  WEBHOOK_URL = "https://hooks.slack.com/services/T0000/B0000/madeUpWebhookPath0000"

  # Columns whose names look like a credential's but whose values aren't one. A secret-bearing column
  # belongs in ActiveRecordSqlRedaction::TABLES instead.
  NOT_SECRET = {
    "action_pack_passkeys.credential_id" => "a passkey's public identifier, sent to the browser to sign in",
    "action_pack_passkeys.public_key" => "a public key",
    "active_storage_blobs.key" => "a storage object's name; reading the object takes a signed URL",
    "active_storage_variant_records.variation_digest" => "a digest of the image transformation",
    "delivery_attempts.code" => "the receiving server's SMTP reply code",
    "domains.dkim_private_key" => "encrypted, so the statement carries only ciphertext",
    "idempotent_requests.key" => "a client's idempotency key, which replays a response only with its sending token",
    "idempotent_requests.sending_token_id" => "the id of a sending token's row, not the token",
    "inbound_emails.digest" => "a digest of a received message, to drop a duplicate",
    "relay_certificates.acme_account_key" => "encrypted, so the statement carries only ciphertext",
    "relay_dns_checks.sealing_key_error" => "what a DNS check found wrong with the sealing key's record",
    "relay_dns_checks.sealing_key_status" => "a DNS check's result for the sealing key's record",
    "relay_sealing_keys.private_key" => "encrypted, so the statement carries only ciphertext",
    "sending_tokens.token_digest" => "a digest; the token itself isn't stored"
  }

  SECRET_LOOKING_COLUMN = /token|code|secret|passw|digest|key|salt|otp|nonce|credential/

  test "a transfer token is absent from its logged insert, lookup, update and delete" do
    log, executed, seen = capture do
      transfer = identities(:leo).transfers.create!(token: TRANSFER_TOKEN)
      assert_equal transfer, Identity::Transfer.active.find_by(token: TRANSFER_TOKEN)
      transfer.update!(token: OTHER_TRANSFER_TOKEN)
      assert_equal identities(:leo), Identity.find_by_transfer_id(OTHER_TRANSFER_TOKEN)
    end

    assert_match(/INSERT INTO [`"]identity_transfers[`"]/, log)
    assert_match(/UPDATE [`"]identity_transfers[`"]/, log)
    assert_match(/DELETE FROM [`"]identity_transfers[`"]/, log)
    assert_no_secret TRANSFER_TOKEN, log
    assert_no_secret OTHER_TRANSFER_TOKEN, log
    assert_no_secret TRANSFER_TOKEN, seen.join("\n")
    assert_no_secret OTHER_TRANSFER_TOKEN, seen.join("\n")
    assert_sent_to_database TRANSFER_TOKEN, executed
    assert_sent_to_database OTHER_TRANSFER_TOKEN, executed
  end

  test "a join code is absent from its logged insert, lookup and reset" do
    join_code = nil

    log, executed = capture do
      join_code = Account::JoinCode.create!(account: accounts(:davids_account), code: JOIN_CODE)
      assert_equal join_code, Account::JoinCode.find_by(code: JOIN_CODE, account: accounts(:davids_account))
      join_code.reset
    end

    assert_match(/INSERT INTO [`"]account_join_codes[`"]/, log)
    assert_match(/UPDATE [`"]account_join_codes[`"]/, log)
    assert_no_secret JOIN_CODE, log
    assert_no_secret join_code.code, log
    assert_sent_to_database JOIN_CODE, executed
    assert_sent_to_database join_code.code, executed
  end

  # The signing secret is encrypted, so only its ciphertext reaches the database.
  test "a webhook's signing secret and URL are absent from its logged insert and update" do
    log, executed = capture do
      webhook = Webhook.create!(domain: domains(:example), name: "Made up", url: "https://example.com/made-up", signing_secret: SECRET)
      webhook.update!(url: WEBHOOK_URL)
    end

    assert_match(/INSERT INTO [`"]webhooks[`"]/, log)
    assert_match(/UPDATE [`"]webhooks[`"]/, log)
    assert_no_secret SECRET, log
    assert_no_secret WEBHOOK_URL, log
    assert_sent_to_database WEBHOOK_URL, executed
  end

  test "statements against other tables keep their literals" do
    log, _ = capture { Account.find_by(name: "Made up account") }

    assert_includes log, "Made up account"
  end

  test "the structured SQL event carries the redacted statement and binds" do
    events = []
    subscriber = Class.new { define_method(:emit) { |event| events << event } }.new
    Rails.event.subscribe(subscriber) { |event| event[:name] == "active_record.sql" }

    Identity::Transfer.find_by(token: TRANSFER_TOKEN)

    payload = events.map { |event| event[:payload] }.find { |payload| payload[:sql].include?("identity_transfers") }
    assert payload
    assert_no_secret TRANSFER_TOKEN, payload.inspect
  ensure
    Rails.event.unsubscribe(subscriber)
  end

  test "the redaction runs ahead of every other SQL consumer from boot" do
    listeners = ActiveSupport::Notifications.notifier.listeners_for("sql.active_record")

    assert_same ActiveRecordSqlRedaction::SUBSCRIBER, listeners.first
    assert listeners.many?, "Rails' own SQL subscribers should follow it"

    group, subscribers = ActiveSupport::Notifications.notifier.groups_for("sql.active_record").first
    assert_equal ActiveSupport::Notifications::Fanout::EventObjectGroup, group
    assert_same ActiveRecordSqlRedaction::SUBSCRIBER.delegate, subscribers.first
  end

  test "a consumer subscribed later, in any style, sees the redacted payload" do
    seen = []
    later = [
      ActiveSupport::Notifications.subscribe("sql.active_record") { |event| seen << event.payload.dup },
      ActiveSupport::Notifications.subscribe("sql.active_record") { |_name, _start, _finish, _id, payload| seen << payload.dup },
      ActiveSupport::Notifications.subscribe(/active_record/) { |_name, _start, _finish, _id, payload| seen << payload.dup }
    ]

    assert_equal identities(:leo), Identity.find_by_transfer_id(identities(:leo).transfers.create!(token: TRANSFER_TOKEN).token)

    redacted = seen.select { |payload| payload[:sql].to_s.include?("identity_transfers") }
    assert redacted.many?
    redacted.each do |payload|
      assert_no_secret TRANSFER_TOKEN, payload[:sql]
      assert_empty payload[:binds]
      assert_empty payload[:type_casted_binds]
    end
  ensure
    later&.each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
  end

  # Relation#explain re-runs the statements it collects from this payload, so they keep their SQL.
  test "explaining a query on a redacted table still works, and the same query outside it is redacted" do
    assert_match(/EXPLAIN/i, Identity::Transfer.where("token IN ('#{TRANSFER_TOKEN}')").explain.inspect)

    log, _ = capture { Identity::Transfer.where("token IN ('#{TRANSFER_TOKEN}')").to_a }
    assert_includes log, "identity_transfers"
    assert_no_secret TRANSFER_TOKEN, log
  end

  test "a duplicate entry's error carries no value" do
    identities(:leo).transfers.create!(token: TRANSFER_TOKEN)

    error = nil
    _, _, seen = capture do
      error = assert_raises ActiveRecord::RecordNotUnique do
        identities(:leo).transfers.new(token: TRANSFER_TOKEN).save!(validate: false)
      end
    end

    assert_no_secret_in_error TRANSFER_TOKEN, error
    assert_no_secret TRANSFER_TOKEN, seen.join("\n")
  end

  test "an invalid statement's error, which can quote the statement, carries no value" do
    error = assert_raises ActiveRecord::StatementInvalid do
      Identity::Transfer.connection.select_all("SELECT * FROM identity_transfers WHERE token = '#{TRANSFER_TOKEN}' INVALID")
    end

    assert_no_secret_in_error TRANSFER_TOKEN, error
  end

  test "a write refused in read-only mode, whose error quotes the statement, carries no value" do
    # Hand-written, so the value is inlined on SQLite too rather than bound.
    error = assert_raises ActiveRecord::ReadOnlyError do
      ActiveRecord::Base.while_preventing_writes { Identity::Transfer.connection.execute("DELETE FROM identity_transfers WHERE token = '#{TRANSFER_TOKEN}'") }
    end

    assert_includes error.message, "DELETE FROM"
    assert_no_secret_in_error TRANSFER_TOKEN, error
  end

  test "a statement whose last literal never closed carries no value into its log line or its error" do
    log, _ = capture do
      error = assert_raises ActiveRecord::StatementInvalid do
        Identity::Transfer.connection.select_all("SELECT * FROM IDENTITY_TRANSFERS WHERE identity_id = '0' AND token = '#{TRANSFER_TOKEN}")
      end

      assert_no_secret_in_error TRANSFER_TOKEN, error
    end

    assert_includes log, "IDENTITY_TRANSFERS"
    assert_no_secret TRANSFER_TOKEN, log
  end

  # Bulk inserts inline their values on SQLite too, and the columns go in order, so the name's
  # trailing backslash sits right before the URL.
  test "a bulk insert's literals are filtered, including after a value that ends in a backslash" do
    log, executed = capture do
      Webhook.insert_all!([ { id: ActiveRecord::Type::Uuid.generate, account_id: accounts(:davids_account).id, domain_id: domains(:example).id, name: "Ends in \\", url: WEBHOOK_URL, signing_secret: SECRET } ])
    end

    assert_match(/INSERT INTO [`"]webhooks[`"]/, log)
    assert_no_secret WEBHOOK_URL, log
    assert_sent_to_database WEBHOOK_URL, executed
    assert_equal "Ends in \\", Webhook.find_by(url: WEBHOOK_URL).name
  end

  test "hand-written SQL that names a table bare is filtered too" do
    log, _ = capture do
      Identity::Transfer.connection.select_all("SELECT 1 FROM `identities` WHERE EXISTS (SELECT 1 FROM identity_transfers t WHERE t.identity_id = `identities`.`id` AND t.token = '#{TRANSFER_TOKEN}')")
    end

    assert_includes log, "identity_transfers t"
    assert_no_secret TRANSFER_TOKEN, log
  end

  test "redaction covers the statement shapes Active Record writes" do
    assert_equal "SELECT * FROM `magic_links` WHERE `code` IN ('[FILTERED]'",
      ActiveRecordSqlRedaction.redact("SELECT * FROM `magic_links` WHERE `code` IN ('a\\'b', 'it''s')")
    assert_equal "INSERT INTO `magic_links` (`id`, `code`) VALUES (x'[FILTERED]'",
      ActiveRecordSqlRedaction.redact("INSERT INTO `magic_links` (`id`, `code`) VALUES (x'01', 'ZQ7XW3'), (x'02', 'ZQ7XW4')")
    assert_equal "INSERT INTO `identity_access_tokens` (`token`) VALUES ('[FILTERED]'",
      ActiveRecordSqlRedaction.redact("INSERT INTO `identity_access_tokens` (`token`) VALUES ('a') ON DUPLICATE KEY UPDATE `token` = 'b'")
    assert_equal %(SELECT "magic_links".* FROM "magic_links" WHERE "magic_links"."code" = '[FILTERED]'),
      ActiveRecordSqlRedaction.redact(%(SELECT "magic_links".* FROM "magic_links" WHERE "magic_links"."code" = 'ZQ7XW3' LIMIT 1))
    assert_equal %{INSERT INTO "webhooks" ("name", "url") VALUES ('[FILTERED]'},
      ActiveRecordSqlRedaction.redact(%{INSERT INTO "webhooks" ("name", "url") VALUES ('ends in \\', 'ZQ7XW3')})
    assert_equal "SELECT * FROM `magic_links` WHERE `code` = '[FILTERED]'",
      ActiveRecordSqlRedaction.redact("SELECT * FROM `magic_links` WHERE `code` = 'a' OR `code` = 'ZQ7XW3")
    assert_equal "SELECT 'x' FROM `accounts`", ActiveRecordSqlRedaction.redact("SELECT 'x' FROM `accounts`")
    assert_equal "SELECT 'x' FROM `magic_links_archive`", ActiveRecordSqlRedaction.redact("SELECT 'x' FROM `magic_links_archive`")
    assert_nil ActiveRecordSqlRedaction.redact(nil)
  end

  test "errors are recognized by the tables they name, not by words" do
    assert ActiveRecordSqlRedaction.mentions_redacted_table?("Duplicate entry 'x' for key 'magic_links.index_magic_links_on_code'")
    assert ActiveRecordSqlRedaction.mentions_redacted_table?("Duplicate entry 'x' for key 'index_identity_transfers_on_token'")
    assert ActiveRecordSqlRedaction.mentions_redacted_table?("INSERT INTO `webhooks` (`url`) VALUES ('x')")
    assert_not ActiveRecordSqlRedaction.mentions_redacted_table?("No route matches [GET] \"/my/webhooks\"")
    assert_not ActiveRecordSqlRedaction.mentions_redacted_table?("Duplicate entry 'x' for key 'cards.index_cards_on_number'")
  end

  test "every column that looks secret is redacted or declared not secret" do
    Rails.application.eager_load!

    columns = ActiveRecord::Base.descendants
      .reject { |model| model.abstract_class? || model.name.nil? }
      .uniq(&:table_name)
      .select(&:table_exists?)
      .flat_map { |model| model.column_names.map { |column| "#{model.table_name}.#{column}" } }
      .select { |column| column.split(".").last.match?(SECRET_LOOKING_COLUMN) }

    assert_includes columns, "identity_transfers.token", "the scan should see the columns it guards"

    unclassified = columns.reject { |column| column.split(".").first.in?(ActiveRecordSqlRedaction::TABLES) || NOT_SECRET.key?(column) }
    assert_empty unclassified, "Add each table to ActiveRecordSqlRedaction::TABLES, or the column to NOT_SECRET with a reason"
  end

  private
    # What the adapter executed comes from a subscriber prepended ahead of the redaction, so it sees the
    # payload as the adapter built it; what consumers see comes from one subscribed after.
    def capture
      log = StringIO.new
      executed, seen = [], []
      logger, ActiveRecord::LogSubscriber.logger = ActiveRecord::LogSubscriber.logger, ActiveSupport::Logger.new(log)
      raw = ActiveSupport::Notifications.subscribe("sql.active_record", prepend: true) { |event| executed << statement_of(event.payload) }
      consumer = ActiveSupport::Notifications.subscribe("sql.active_record") { |event| seen << statement_of(event.payload) }

      yield

      [ log.string, executed, seen ]
    ensure
      ActiveSupport::Notifications.unsubscribe(raw) if raw
      ActiveSupport::Notifications.unsubscribe(consumer) if consumer
      ActiveRecord::LogSubscriber.logger = logger
    end

    def statement_of(payload)
      [ payload[:sql], *bind_values(payload[:type_casted_binds]), *Array(payload[:binds]).map { |bind| bind.try(:value_before_type_cast) || bind }, *payload[:exception] ].join(" ")
    end

    def bind_values(binds)
      binds.respond_to?(:call) ? binds.call : Array(binds)
    end

    def assert_no_secret(secret, text)
      assert_not_includes text, secret
    end

    def assert_no_secret_in_error(secret, error)
      [ error, error.cause ].compact.each do |exception|
        [ exception.message, exception.to_s, exception.detailed_message, exception.full_message, exception.inspect ].each do |message|
          assert_no_secret secret, message
        end
      end
    end

    # The database still receives the value: in the SQL text on MySQL, as a bind on SQLite.
    def assert_sent_to_database(secret, executed)
      assert executed.any? { |statement| statement.include?(secret) }, "#{secret} should reach the database"
    end
end
