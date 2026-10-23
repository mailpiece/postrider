# Directives accept ENV (CSP_*) or config.x.content_security_policy.*, so
# deployments can extend the base policy without duplicating it.
Rails.application.configure do
  sources = ->(directive) do
    env_key = "CSP_#{directive.to_s.upcase}"
    value = if ENV.key?(env_key)
      ENV[env_key]
    else
      config.x.content_security_policy.send(directive)
    end

    case value
    when nil then []
    when Array then value
    when String then value.split
    else []
    end
  end

  report_uri = ENV.fetch("CSP_REPORT_URI") { config.x.content_security_policy.report_uri }
  report_only =
    if ENV.key?("CSP_REPORT_ONLY")
      ENV["CSP_REPORT_ONLY"] == "true"
    else
      config.x.content_security_policy.report_only
    end

  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[ script-src ]

  config.content_security_policy do |policy|
    policy.default_src :self, *sources.(:default_src)
    policy.script_src :self, *sources.(:script_src)
    policy.connect_src :self, *sources.(:connect_src)
    policy.frame_src :self, *sources.(:frame_src)

    # Permit inline styles / data+https fonts&media / blob workers so user tools
    # (a11y extensions, privacy tools, custom fonts) aren't blocked.
    policy.style_src :self, :unsafe_inline, *sources.(:style_src)
    policy.img_src :self, "blob:", "data:", "https:", *sources.(:img_src)
    policy.font_src :self, "data:", "https:", *sources.(:font_src)
    policy.media_src :self, "blob:", "data:", "https:", *sources.(:media_src)
    policy.worker_src :self, "blob:", *sources.(:worker_src)

    policy.object_src :none
    policy.base_uri :none

    policy.form_action :self, *sources.(:form_action)
    policy.frame_ancestors :self, *sources.(:frame_ancestors)

    policy.report_uri report_uri if report_uri
  end

  config.content_security_policy_report_only = report_only

  # The pages in public/ carry no script and no inline styles, so everything falls back to default-src 'none'.
  static_policy = "default-src 'none'; img-src 'self'; style-src 'self'; " \
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

  static_policy += "; report-uri #{report_uri}" if report_uri

  static_policy_header = report_only ? ActionDispatch::Constants::CONTENT_SECURITY_POLICY_REPORT_ONLY \
                                     : ActionDispatch::Constants::CONTENT_SECURITY_POLICY

  # Files served straight from public/ return before the CSP middleware runs.
  config.public_file_server.headers = (config.public_file_server.headers || {}) \
    .merge(static_policy_header => static_policy)

  # A real 404 or 500 renders its page through the exceptions app, past the file server.
  if config.exceptions_app.nil?
    public_exceptions = ActionDispatch::PublicExceptions.new(Rails.public_path)
    config.exceptions_app = ->(env) do
      public_exceptions.call(env).tap do |_status, headers, _body|
        if headers[Rack::CONTENT_TYPE].to_s.start_with?("text/html")
          headers[static_policy_header] = static_policy
        end
      end
    end
  end
end unless ENV["DISABLE_CSP"]
