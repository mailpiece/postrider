require_relative "boot"

require "rails/all"
require_relative "../lib/action_pack/railtie"

Bundler.require(*Rails.groups)

module PostRider
  class Application < Rails::Application
    config.load_defaults 8.1

    # Set here rather than in an initializer: Active Record copies these into filter_attributes when it
    # loads, and an initializer can load it before a later one runs.
    #
    # `code` covers a join code's route parameter. A webhook's `url` can be a credential itself (a chat
    # service's incoming webhook URL); it is matched whole, so a parameter that merely ends in "url" keeps its
    # value. The pattern also matches a nested key's dotted path ("webhook.url"), which is what it is tested
    # against once any dotted filter, such as those `encrypts` adds, is present.
    config.filter_parameters += [
      *%i[
        passw passkey secret token _key crypt salt certificate otp ssn code email
        subject text html attachments headers
      ],
      /(?:\A|\.)url\z/
    ]

    config.autoload_lib ignore: %w[ assets tasks rails_ext puma ]

    # Keys for the DKIM, ARC and ACME keys, the certificate and webhook secrets, derived from SECRET_KEY_BASE so a
    # copy of the database without the box's ENV holds only ciphertext. Registered before
    # active_record_encryption.configuration, which copies them when Active Record loads; a file under
    # config/initializers can run after that. Under another SECRET_KEY_BASE they cannot be read: docs/deployment.md
    # says what to make again.
    initializer "active_record_encryption.keys", before: "active_record_encryption.configuration" do |app|
      %i[ primary_key deterministic_key key_derivation_salt ].each do |name|
        app.config.active_record.encryption[name] = app.key_generator.generate_key("active_record_encryption/#{name}", 32)
      end
    end

    # Rails 8.1 disabled event debug_mode by default; keep SQL query logs.
    # https://github.com/rails/rails/pull/55900
    config.after_initialize do
      Rails.event.debug_mode = true
    end

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Every blob is a stranger's mail, and nothing reads image dimensions or shows a
    # preview, so no image library opens what arrives on port 25.
    config.active_storage.analyzers = []
    config.active_storage.previewers = []
    config.active_storage.variant_processor = :disabled

    config.action_pack.passkey.draw_routes = false
    config.action_pack.passkey.challenge_url = -> { my_passkey_challenge_path(script_name: "") }

    config.mission_control.jobs.http_basic_auth_enabled = false

    initializer "postrider.trusted_proxies", after: :setup_main_autoloader, before: :build_middleware_stack do |app|
      Rack::Request.forwarded_priority = [ :x_forwarded ]

      app.config.action_dispatch.trusted_proxies =
        ActionDispatch::RemoteIp::TRUSTED_PROXIES + Relay.trusted_proxies
    end
  end
end
