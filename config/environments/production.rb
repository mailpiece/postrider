require "active_support/core_ext/integer/time"
require_relative "../../lib/rails_ext/json_event_subscriber"

Rails.application.configure do
  if base_url = ENV["BASE_URL"].presence
    uri = URI.parse(base_url)
    url_options = { host: uri.host, protocol: uri.scheme }
    url_options[:port] = uri.port if uri.port != uri.default_port

    routes.default_url_options = url_options
    config.action_mailer.default_url_options = url_options
  end

  config.enable_reloading = false
  config.eager_load = true

  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{5.minutes.to_i}"
  }

  # Don't overwrite if already set (e.g. by the staging overlay).
  if config.active_storage.service.blank?
    config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym
  end

  # DISABLE_SSL=true turns off assume_ssl and force_ssl together.
  ssl_enabled = "true" unless ENV["DISABLE_SSL"] == "true"

  config.assume_ssl = ENV.fetch("ASSUME_SSL", ssl_enabled) == "true"
  config.force_ssl = ENV.fetch("FORCE_SSL", ssl_enabled) == "true"

  config.logger = ActiveSupport::Logger.new(STDOUT)
                                       .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
                                       .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  config.log_tags = [ :request_id ]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Set STRUCTURED_LOGGING=true to also write each event as a line of JSON.
  if ENV["STRUCTURED_LOGGING"] == "true"
    STDOUT.sync = true
    Rails.event.subscribe(JsonEventSubscriber.new(STDOUT)) { |event| !event[:name].start_with?("active_record.sql", "action_view.") }
  end

  config.cache_store = :solid_cache_store

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue, reading: :queue } }

  config.action_mailer.perform_caching = false

  config.i18n.fallbacks = true

  config.active_support.report_deprecations = false

  config.active_record.dump_schema_after_migration = false
end
