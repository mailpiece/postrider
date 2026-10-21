class Webhook::Delivery < ApplicationRecord
  include Rails.application.routes.url_helpers

  class ResponseTooLarge < StandardError; end

  STALE_THRESHOLD = 7.days
  USER_AGENT = "postrider/1.0.0 Webhook"
  ENDPOINT_TIMEOUT = 7.seconds
  MAX_RESPONSE_SIZE = 100.kilobytes

  belongs_to :account, default: -> { webhook.account }
  belongs_to :webhook
  belongs_to :event

  store :request, coder: JSON
  store :response, coder: JSON

  enum :state, %w[ pending in_progress completed errored ].index_by(&:itself), default: :pending

  scope :ordered, -> { order created_at: :desc, id: :desc }
  scope :stale, -> { where(created_at: ...STALE_THRESHOLD.ago) }

  after_create_commit :deliver_later

  def self.cleanup(batch_size: 500, pause: 0.1)
    sleep pause until stale.limit(batch_size).delete_all.zero?
  end

  def deliver_later
    Webhook::DeliveryJob.perform_later(self)
  end

  def deliver
    in_progress!

    outgoing_headers = headers
    self.request[:headers] = sanitize_headers(outgoing_headers)
    self.response = perform_request(outgoing_headers)
    self.state = :completed
    save!

    webhook.delinquency_tracker.record_delivery_of(self)
  rescue
    errored!
    raise
  end

  def sanitized_request
    if headers = request&.dig("headers")&.except("X-Webhook-Signature", "Authorization")
      { headers: headers }
    end
  end

  def response_summary
    if response.present?
      { code: response[:code], error: response[:error] }
    end
  end

  def failed?
    (errored? || completed?) && !succeeded?
  end

  def succeeded?
    completed? && response[:error].blank? && response[:code].between?(200, 299)
  end

  private
    def sanitize_headers(headers)
      headers.except("X-Webhook-Signature", "Authorization")
    end

    def perform_request(headers)
      if resolved_ip.nil?
        { error: :private_uri }
      else
        request = Net::HTTP::Post.new(uri, headers).tap { |request| request.body = payload }

        response = http.request(request) do |net_http_response|
          stream_body_with_limit(net_http_response)
        end

        { code: response.code.to_i }
      end
    rescue ResponseTooLarge
      { error: :response_too_large }
    rescue Surfguard::Unresolvable, Resolv::ResolvTimeout, Resolv::ResolvError, SocketError
      { error: :dns_lookup_failed }
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
      { error: :connection_timeout }
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET
      { error: :destination_unreachable }
    rescue OpenSSL::SSL::SSLError
      { error: :failed_tls }
    rescue EOFError
      { error: :connection_closed_prematurely }
    end

    def stream_body_with_limit(response)
      bytes_read = 0
      response.read_body do |chunk|
        bytes_read += chunk.bytesize
        raise ResponseTooLarge if bytes_read > MAX_RESPONSE_SIZE
      end
    end

    def resolved_ip
      return @resolved_ip if defined?(@resolved_ip)
      @resolved_ip = Surfguard.resolve_public_ips(uri.host).first
    end

    def uri
      @uri ||= URI(webhook.url)
    end

    # The nil proxy address ignores http_proxy: a proxy would look the host up again, and the connection
    # would no longer go to resolved_ip.
    def http
      Net::HTTP.new(uri.host, uri.port, nil).tap do |http|
        http.ipaddr = resolved_ip
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = ENDPOINT_TIMEOUT
        http.read_timeout = ENDPOINT_TIMEOUT
      end
    end

    def headers
      if webhook.for_action_mailbox_relay?
        {
          "User-Agent" => USER_AGENT,
          "Content-Type" => content_type,
          "Authorization" => "Basic #{Base64.strict_encode64("actionmailbox:#{webhook.signing_secret}")}"
        }
      else
        {
          "User-Agent" => USER_AGENT,
          "Content-Type" => content_type,
          "X-Webhook-Signature" => signature,
          "X-Webhook-Timestamp" => event.created_at.utc.iso8601
        }
      end
    end

    def signature
      OpenSSL::HMAC.hexdigest("SHA256", webhook.signing_secret, payload)
    end

    def content_type
      webhook.for_action_mailbox_relay? ? "message/rfc822" : "application/json"
    end

    def payload
      @payload ||= if webhook.for_action_mailbox_relay?
        event.eventable.relayable_raw
      elsif webhook.for_slack?
        slack_payload
      else
        event.body
      end
    end

    # Slack treats &, <, > as markup; escape so the description survives as text.
    def slack_payload
      text = ERB::Util.html_escape(event.description)
      url = polymorphic_url(linkable, base_url_options.merge(script_name: account.slug))

      { text: "#{text} <#{url}|Open in PostRider>" }.to_json
    end

    def linkable
      eventable = event.eventable
      eventable.respond_to?(:mailpiece) ? eventable.mailpiece : eventable
    end

    def base_url_options
      Rails.application.routes.default_url_options.presence ||
        Rails.application.config.action_mailer.default_url_options
    end
end
