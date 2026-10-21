require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # Toggle with `bin/rails dev:cache`.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  if Rails.root.join("tmp/minio-dev.txt").exist?
    config.active_storage.service = :devminio
    config.x.content_security_policy.connect_src = "http://minio.localhost:39000"
    config.x.content_security_policy.img_src = "http://minio.localhost:39000"
  else
    config.active_storage.service = :local
  end

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false

  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_job.verbose_enqueue_logs = true

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue, reading: :queue } }

  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true

  config.log_tags = [ :request_id ]

  config.hosts = [
    "app.postrider.localhost",
    "postrider.localhost", # backwards compat; CORS errors with minio
    "localhost",
    "127.0.0.1",
    /postrider-\d+/,   # review apps
    /.*\.ts\.net/, # Tailscale Serve
    /.*\.nip\.io/  # mobile / LAN
  ]

  # Prefer the canonical host over personal Tailscale URLs; also needed for
  # URL helpers outside a request (e.g. InboundEmail::Payload from a job).
  url_options = { host: "#{config.hosts.first}:3010" }
  config.action_mailer.default_url_options = url_options
  routes.default_url_options = url_options
end
