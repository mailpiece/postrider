module Smtp
  # Postrider's own refusals; the rest come from MailGate::Errors and MailSmtp.
  module Errors
    class DomainNotVerified < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end

    class SendingDisabled < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end
  end
end
