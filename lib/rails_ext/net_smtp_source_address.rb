# Bind Net::SMTP to a specific local IP; net-smtp has no native source_address hook.
require "net/smtp"

module NetSmtpSourceAddress
  attr_accessor :source_address

  private
    def tcp_socket(address, port)
      if source_address
        TCPSocket.open(address, port, source_address)
      else
        super
      end
    end
end

Net::SMTP.prepend NetSmtpSourceAddress
