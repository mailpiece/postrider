# to_prepare (not after_initialize): Relay isn't loadable in initializers, and
# posthog-rails only hooks Rails.error after PostHog.init — its after_initialize runs first.
Rails.application.config.to_prepare do
  PostHog::Rails.configure do |config|
    config.auto_capture_exceptions = true
    config.report_rescued_exceptions = true
    config.auto_instrument_active_job = true
    config.current_user_resolver = proc { Current.user }
  end

  PostHog.init do |config|
    config.api_key = Relay.posthog_api_key
    config.host = Relay.posthog_host
    config.test_mode = true if Rails.env.test?

    config.before_send = ->(event) do
      event[:properties] = event[:properties].to_h.merge(
        environment: Rails.env,
        version: Relay.code_version,
        email: Current.identity&.email_address,
        request_id: Current.request_id
      ).compact

      event
    end
  end
end
