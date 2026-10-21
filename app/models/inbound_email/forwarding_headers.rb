# Trace headers for mail we forward on: where it went and the mailbox it came from, following
# Gmail's and HEY's convention. Named under our own prefix because both of them write the plain
# X-Forwarded-To/-For themselves and read them back as loop and routing signals.
class InboundEmail::ForwardingHeaders < InboundEmail::Headers
  def initialize(inbound_email, destination)
    super(inbound_email)
    @destination = destination
  end

  private
    def fields
      {
        InboundEmail::Forwarding::TRACE_HEADER => @inbound_email.domain.name,
        "#{InboundEmail::Forwarding::TRACE_HEADER}-To" => @destination,
        "#{InboundEmail::Forwarding::TRACE_HEADER}-For" => "#{@inbound_email.rcpt_to} #{@destination}"
      }
    end
end
