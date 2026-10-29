module Mailbox::ForwardConfirmable
  FORWARD_CONFIRMATION_TOKEN_PURPOSE = "confirm_forwarding"
  FORWARD_CONFIRMATION_TOKEN_EXPIRATION = 24.hours

  extend ActiveSupport::Concern

  included do
    before_save :reset_forward_confirmation, if: :forward_to_changed?
    after_save_commit :send_forward_confirmation_later, if: :should_send_forward_confirmation?
  end

  def send_forward_confirmation_later
    Mailbox::SendForwardConfirmationJob.perform_later(self)
  end

  # Null sender: a bounce would come back as a DSN quoting the link, into the tenant's mail log.
  def send_forward_confirmation
    if forward_confirmable?
      Message.submit_raw(domain:, mail_from: forward_confirmation_sender, envelope_from: "", raw: forward_confirmation_raw,
        tags: [], recipients: [ forward_to ], origin: :system)
    end
  end

  def should_send_forward_confirmation?
    saved_change_to_forward_to? && forward_confirmable?
  end

  def forward_confirmable?
    forward_to.present? && domain.verified? && domain.sending? && account.active? && !domain.suppressions.exists?(address: forward_to)
  end

  def forward_confirmation_sender
    "noreply@#{domain.name}"
  end

  def confirm_forwarding_using_token(token)
    if forward_confirmation_token?(token)
      confirm_forwarding
    else
      false
    end
  end

  def forward_confirmation_token?(token)
    parsed_token = SignedGlobalID.parse(token, for: FORWARD_CONFIRMATION_TOKEN_PURPOSE)
    parsed_token.present? && parsed_token.find == self && parsed_token.params["forward_to"] == forward_to
  end

  def confirm_forwarding
    update! forward_confirmed_at: Time.current
  end

  private
    def forward_confirmation_raw
      MailboxMailer.forward_confirmation(mailbox: self, token: generate_forward_confirmation_token).message.encoded
    end

    def generate_forward_confirmation_token(to: forward_to, **options)
      options = options.with_defaults(
        for: FORWARD_CONFIRMATION_TOKEN_PURPOSE,
        forward_to: to,
        expires_in: FORWARD_CONFIRMATION_TOKEN_EXPIRATION
      )

      to_sgid(**options).to_s
    end

    def reset_forward_confirmation
      self.forward_confirmed_at = nil
    end
end
