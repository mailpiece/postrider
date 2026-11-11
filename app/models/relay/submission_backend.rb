class Relay::SubmissionBackend
  include Relay::Backend

  class << self
    def listener(**options)
      MailGate::SubmissionListener.new(
        backend: new,
        hostname: Relay.submission_hostname,
        host: Relay.bind_address,
        port: Relay.submission_port,
        max_message_size: Relay.max_outbound_message_size,
        max_recipients: Message::Submitting::MAX_RECIPIENTS,
        max_processings: Relay.submission_max_processings,
        # No per-IP DATA limit on 587, as before: mailgate would default it to half of max_processings.
        max_processings_per_ip: nil,
        max_connections: Relay.submission_max_connections,
        max_connections_per_ip: Relay.submission_max_connections_per_ip,
        max_tls_sessions_per_ip: Relay.submission_max_tls_sessions_per_ip,
        max_auth_attempts_per_ip: Relay.submission_max_auth_attempts_per_ip,
        stress_threshold: Relay.stress_threshold,
        max_session_duration: Relay.smtp_session_duration,
        logger_severity: Relay.smtp_log_level,
        **options
      )
    end
  end

  # The username is ignored: the token is the password.
  def authenticate(_username, password, ip:)
    wrap do
      if sending_token = SendingToken.authenticate(password)
        Current.with_account(sending_token.account) { require_allowed_ip(sending_token, ip) }
        sending_token.id
      end
    end
  end

  def may_send_as?(id, address)
    with_sending_token(id) do |sending_token|
      domain = sending_token.domain

      if !domain.verified?
        raise Smtp::Errors::DomainNotVerified, "#{domain.name} isn't verified for sending: " \
          "publish #{domain.dkim_record.hostname} TXT, then check DNS"
      elsif !domain.sending?
        raise Smtp::Errors::SendingDisabled, "#{domain.name} isn't sending: turned off in its settings"
      else
        sending_token.authorizes_sending_as?(address)
      end
    end
  end

  def account_active?(id)
    with_sending_token(id) { |sending_token| sending_token.account.active? }
  end

  def rate_limited?(id)
    with_sending_token(id) { |sending_token| SubmissionRateLimiter.exceeded?(sending_token.account) }
  end

  def submit(id, raw:, received:, envelope:, key:)
    with_sending_token(id) do |sending_token|
      submission = SmtpSubmission.new(raw, domain: sending_token.domain)
      raise MailGate::Errors::InvalidMessage, "Message must include a To header, a From header, and exactly one address in each identity header" unless submission.valid?

      authorize_identities(submission, sending_token)

      outcome = IdempotentRequest.fulfill(sending_token, key) do
        Message.submit_raw(domain: sending_token.domain, mail_from: envelope.mail_from,
          raw: received + submission.raw, tags: submission.tags, recipients: envelope.rcpt_to)
      end

      case outcome.status
      when :fresh
        sending_token.use
      when :in_progress
        raise MailGate::Errors::DuplicateSubmission, "Duplicate submission in progress, try again shortly"
      end
    end
  rescue ActiveRecord::RecordInvalid => error
    # The submitter's own input, so reject permanently rather than inviting a retry.
    raise MailGate::Errors::InvalidMessage, error.record.errors.full_messages.to_sentence
  end

  private
    def require_allowed_ip(sending_token, ip)
      unless sending_token.domain.allows_ip?(ip)
        sending_token.refuse(ip)
        raise MailGate::Errors::AddressNotAllowed, "Sending from #{ip} isn't allowed for this domain"
      end
    end

    def with_sending_token(id)
      wrap do
        sending_token = SendingToken.find(id)
        Current.with_account(sending_token.account) { yield sending_token }
      end
    end

    # We DKIM-sign From/Sender too; envelope auth alone is not enough.
    def authorize_identities(submission, sending_token)
      submission.identities.each do |address|
        raise MailGate::Errors::SenderNotAuthorized, "Not authorized to send as #{address}" unless sending_token.authorizes_sending_as?(address)
      end
    end
end
