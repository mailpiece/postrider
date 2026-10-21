# Trace headers for Action Mailbox relays.
class InboundEmail::RelayHeaders < InboundEmail::Headers
  private
    def fields
      {
        "Delivered-To" => @inbound_email.rcpt_to,
        "Authentication-Results" => @inbound_email.authentication_results,
        "X-PostRider-Mailpiece-Id" => @inbound_email.mailpiece&.id
      }
    end
end
