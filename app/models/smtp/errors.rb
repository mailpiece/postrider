module Smtp
  # Product policy replies; protocol errors come from MailSmtp::* in the engine.
  module Errors
    # A subclass so refusals count toward the engine's cap on failed AUTH attempts.
    class AddressNotAllowed < MailSmtp::AuthenticationFailed
      status 535, "Authentication not accepted from this address", enhanced: "5.7.1"
    end

    class DuplicateSubmission < MailSmtp::Error
      status 451, "Requested action aborted: local error in processing", enhanced: "4.3.0"
    end

    class RateLimited < MailSmtp::Error
      status 452, "Requested action not taken: insufficient system storage", enhanced: "4.7.0"
    end

    class StorageFull < MailSmtp::Error
      status 452, "Requested action not taken: insufficient system storage", enhanced: "4.3.1"
    end

    class RelayDenied < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end

    class SenderNotAuthorized < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end

    class DomainNotVerified < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end

    class AccountInactive < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end

    class InvalidMessage < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.6.0"
    end

    class LoopDetected < MailSmtp::Error
      status 554, "Transaction failed", enhanced: "5.4.6"
    end
  end
end
