module DomainTestHelper
  SIMPLE_RAW = "Subject: Hi\r\n\r\nBody"
  SENDING_TOKEN = "testsendingtokenexample0"

  def self.dkim_key
    @dkim_key ||= DkimKey.generate
  end

  def create_inbound_email(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: SIMPLE_RAW, **attributes)
    InboundEmail.create!(domain: domain, mail_from: mail_from, rcpt_to: rcpt_to, raw: raw, **attributes)
  end

  def create_delivery(domain: domains(:example), mail_from: "sender@example.com", rcpt_to: "recipient@example.com",
    raw: SIMPLE_RAW, status: nil, **attributes)
    message = domain.messages.create!(mail_from: mail_from, raw: raw)
    delivery = message.deliveries.create!(rcpt_to: rcpt_to, **attributes)
    delivery.update!(status: status) if status
    delivery
  end

  def deliver_from(domain, status: "delivered")
    create_delivery(domain: domain, mail_from: "sender@#{domain.name}", status: status)
  end

  def deeply_nested_raw(depth: 2000)
    body = (1..depth).reverse_each.reduce("Body\r\n") do |inner, level|
      "Content-Type: multipart/mixed; boundary=\"b#{level}\"\r\n\r\n--b#{level}\r\n#{inner}\r\n--b#{level}--\r\n"
    end

    "From: a@example.com\r\nSubject: Deep\r\nMIME-Version: 1.0\r\n#{body}"
  end
end
