class SubmissionListener < SmtpListener
  def authenticate(session, password:, **)
    if sending_token = SendingToken.authenticate(password)
      require_allowed_ip(session, sending_token)
      log_authenticated(session, sending_token)
      sending_token.id
    else
      # Don't echo the username: a mistyped token would land in ERROR logs.
      raise MailSmtp::AuthenticationFailed, "Authentication failed"
    end
  end

  def mail_from(session, address)
    address = sender_in(address)
    sending_token = SendingToken.find(session.authorization_id)

    if !sending_token.domain.verified?
      raise Smtp::Errors::DomainNotVerified, "#{sending_token.domain.name} isn't verified for sending: " \
        "publish #{sending_token.domain.dkim_record.hostname} TXT, then check DNS"
    elsif sending_token.authorizes_sending_as?(address)
      address
    else
      raise Smtp::Errors::SenderNotAuthorized, "Not authorized to send as #{address}"
    end
  end

  def rcpt_to(session, address)
    if session.envelope.to.size < Message::Submitting::MAX_RECIPIENTS
      recipient_in(address)
    else
      raise MailSmtp::TooManyRecipients, "Too many recipients, maximum is #{Message::Submitting::MAX_RECIPIENTS}"
    end
  end

  def receive(session, io)
    body = io.read
    submission = SmtpSubmission.new(body)
    raise Smtp::Errors::InvalidMessage, "Message must include a To header, a From header, and exactly one address in each identity header" unless submission.valid?

    Rails.application.executor.wrap { accept(submission, session, body:) }

    log_accepted(session, body.bytesize)
  rescue MailSmtp::Error
    raise
  rescue ActiveRecord::RecordInvalid => error
    # The submitter's own input, so reject permanently rather than inviting a retry.
    raise Smtp::Errors::InvalidMessage, error.record.errors.full_messages.to_sentence
  rescue StandardError => error
    Rails.error.report(error, severity: :error)
    raise MailSmtp::LocalError, "Temporary local error, please retry"
  end

  private
    # Engine logger, not Rails.logger (fatal in production). Names the token, never the secret.
    def log_authenticated(session, sending_token)
      log(session, Logger::INFO,
        "[smtp] #{self.class.name} authenticated token #{sending_token.name.inspect} (#{sending_token.id}) from #{session.remote_ip}")
    end

    def hostname
      Relay.submission_hostname
    end

    def received_protocol(_session)
      "ESMTPSA"
    end

    # Don't broadcast the client IP (ESP injection, not MX relay). Applied after
    # SmtpSubmission strips client Received headers so ours sits on top.
    def received_header(session)
      "Received: by #{hostname} with #{received_protocol(session)}; #{Time.now.utc.rfc2822}\r\n"
    end

    def listener_options
      {
        port: Relay.submission_port,
        max_processings: Relay.submission_max_processings,
        max_connections: Relay.submission_max_connections,
        max_connections_per_ip: Relay.submission_max_connections_per_ip,
        max_tls_sessions_per_ip: Relay.submission_max_tls_sessions_per_ip,
        max_auth_attempts_per_ip: Relay.submission_max_auth_attempts_per_ip,
        stress_threshold: Relay.stress_threshold,
        auth: :required,
        starttls: :required,
        eight_bit_mime: false
      }
    end

    def message_size_limit
      Relay.max_outbound_message_size
    end

    def accept(submission, session, body:)
      sending_token = SendingToken.find(session.authorization_id)

      authorize_identities(submission, sending_token)

      account = sending_token.account
      raise Smtp::Errors::AccountInactive, "Account is not active" unless account.active?
      raise Smtp::Errors::RateLimited, "Rate limit exceeded, try again shortly" if SubmissionRateLimiter.exceeded?(account)

      Current.with_account(account) do
        submit(submission, sending_token, session, body:)
      end
    end

    def require_allowed_ip(session, sending_token)
      unless sending_token.domain.allows_ip?(session.remote_ip)
        sending_token.refuse(session.remote_ip)
        raise Smtp::Errors::AddressNotAllowed, "Sending from #{session.remote_ip} isn't allowed for this domain"
      end
    end

    # We DKIM-sign From/Sender too; envelope auth alone is not enough.
    def authorize_identities(submission, sending_token)
      submission.identities.each do |address|
        raise Smtp::Errors::SenderNotAuthorized, "Not authorized to send as #{address}" unless sending_token.authorizes_sending_as?(address)
      end
    end

    def submit(submission, sending_token, session, body:)
      outcome = IdempotentRequest.fulfill(sending_token, submission_key(session, body)) do
        Message.submit_raw(domain: sending_token.domain, mail_from: session.envelope.from,
          raw: received_header(session) + submission.raw, tags: submission.tags, recipients: session.envelope.to)
      end

      case outcome.status
      when :fresh
        sending_token.use
      when :in_progress
        raise Smtp::Errors::DuplicateSubmission, "Duplicate submission in progress, try again shortly"
      end
    end

    def submission_key(session, body)
      Digest::SHA256.new
        .update("#{session.envelope.from}\n#{session.envelope.to.sort.join(",")}\n")
        .update(body)
        .hexdigest
    end
end
