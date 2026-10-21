require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?

  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.hour.to_i}"
  }

  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false

  config.active_storage.service = :test

  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test

  # Fixtures hold credentials in the clear; they are stored encrypted, as the app stores them.
  config.active_record.encryption.encrypt_fixtures = true

  # Needed for URL helpers outside a request (e.g. InboundEmail::Payload from a job).
  config.action_mailer.default_url_options = { host: "example.com" }
  routes.default_url_options = { host: "example.com" }

  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.action_controller.raise_on_missing_callback_actions = true

  config.autoload_paths += %w[ test/test_helpers ]

  config.x.multi_tenant.enabled = true
end
