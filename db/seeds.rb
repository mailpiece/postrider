unless Rails.env.development?
  puts "WARN: Seeding is just for development!"
else
  DEV_DOMAIN_NAME = "hello.example".freeze

  # Seed DSL
  def seed_account(name)
    print "  #{name}…"
    elapsed = Benchmark.realtime { require_relative "seeds/#{name}" }
    puts " #{elapsed.round(2)} sec"
  end

  def dev_account
    Account.first || create_dev_account
  end

  def create_dev_account
    # Seeding skips signup, so grant the staff flag the first signup would have set.
    identity = Identity.find_or_create_by!(email_address: "mike@example.com")
    identity.update!(staff: true)

    Account.create_with_owner(
      account: { name: "Hello's PostRider" },
      owner: { name: "Hello", identity: identity }
    ).tap do |account|
      Current.with_account(account) do
        account.domains.create!(name: DEV_DOMAIN_NAME, dkim_status: :ok, all_access: true,
          creator: account.users.find_by(role: :owner))
      end
    end
  end

  # Every seeded mailpiece is sent from or addressed to this domain, and mail now
  # requires one.
  def dev_domain
    Current.account.domains.find_by!(name: DEV_DOMAIN_NAME)
  end

  # Mail hangs off its domain now, and an account reaches it through one, so the
  # destroy has to go through the domain too.
  def reset_mail
    dev_domain.inbound_emails.destroy_all
    dev_domain.messages.destroy_all
    dev_domain.contacts.destroy_all
  end

  # Most mail authenticates, so that's the default: say `auth: :spoofed` for a sender
  # nothing vouches for, or `auth: nil` for one mailauth never answered about.
  def create_inbound(from:, to:, subject:, body:, status: :delivered, rich: false, dmarc: false, contact: nil,
    auth: :authenticated, **verdicts)
    raw =
      if dmarc
        build_dmarc_raw(from:, to:, subject:, body:)
      elsif rich
        build_rich_raw(from:, to:, subject:, body:)
      else
        build_raw(from:, to:, subject:, body:)
      end

    InboundEmail.create!(domain: dev_domain, mail_from: from, rcpt_to: to, raw:, contact:).tap do |inbound|
      inbound.extract_attachments if rich || dmarc
      forwarded = %i[ delivered bounced ].include?(status)
      inbound.update!(status:, forwarded_at: (Time.current if forwarded), **verdicts_for(auth, from:), **verdicts)
    end
  end

  # Seeds skip real authentication, so state what mailauth would have concluded.
  def verdicts_for(kind, from:)
    case kind
    when :authenticated
      { spf: "pass", dkim: "pass", dmarc: "pass", dmarc_policy: "reject", from_aligned: true,
        authentication_results: results_header(from, spf: "pass", dkim: "pass", dmarc: "pass") }
    when :spoofed
      { spf: "fail", dkim: "none", dmarc: "fail", dmarc_policy: "reject",
        authentication_results: results_header(from, spf: "fail", dkim: "none", dmarc: "fail") }
    else
      {}
    end
  end

  # RELAY_HOSTNAME is usually unset in development, and an empty authserv-id would leave the
  # header starting at its first semicolon.
  def results_header(from, spf:, dkim:, dmarc:)
    domain = from.split("@").last

    "#{Relay.hostname.presence || "mx.#{DEV_DOMAIN_NAME}"}; spf=#{spf} smtp.mailfrom=#{from}; " \
      "dkim=#{dkim} header.d=#{domain}; dmarc=#{dmarc} header.from=#{domain}"
  end

  def create_outbound(from:, to:, subject:, body:, status: :delivered, rich: false, attempts: [], events: [])
    raw = rich ? build_rich_raw(from:, to:, subject:, body:) : build_raw(from:, to:, subject:, body:)
    message = Message.create!(domain: dev_domain, mail_from: from, raw:)
    message.extract_attachments if rich
    message.deliveries.create!(rcpt_to: to).tap do |delivery|
      delivery.update!(status:)
      attempts.each { |attempt| delivery.attempts.create!(**attempt) }
      events.each { |action, particulars| delivery.track_event(action, rcpt_to: to, **particulars) }
    end
  end

  # A recorded SMTP conversation, in the same "-> / <-" transcript format
  # SmtpDelivery captures via Net::SMTP's debug_output, so the delivery show
  # page has a real multi-attempt transcript to render and collapse.
  def smtp_attempt(mx_host:, code:, output:, transcript:, ago:)
    { mx_host:, code:, output:, transcript:, created_at: ago }
  end

  def build_raw(from:, to:, subject:, body:)
    "From: #{from}\r\nTo: #{to}\r\nSubject: #{subject}\r\n\r\n#{body}"
  end

  # A multipart/mixed message carrying an inline PNG (referenced from the HTML
  # body via cid:) and a text file attachment, so the mail log exercises the
  # attachment-extraction path the same way real inbound/outbound mail does.
  def build_rich_raw(from:, to:, subject:, body:)
    <<~EOM
      From: #{from}
      To: #{to}
      Subject: #{subject}
      Content-Type: multipart/mixed; boundary=MIX

      --MIX
      Content-Type: multipart/related; boundary=REL

      --REL
      Content-Type: text/html; charset=UTF-8

      <p>#{body}</p><p>Our logo: <img src="cid:logo@seed" alt="logo"></p>
      --REL
      Content-Type: image/png
      Content-ID: <logo@seed>
      Content-Disposition: inline; filename=logo.png
      Content-Transfer-Encoding: base64

      #{seed_inline_png}
      --REL--
      --MIX
      Content-Type: text/plain; name="notes.txt"
      Content-Disposition: attachment; filename="notes.txt"
      Content-Transfer-Encoding: base64

      #{Base64.strict_encode64("Seed attachment for: #{subject}\n")}
      --MIX--
    EOM
  end

  # A multipart/mixed message carrying a DMARC aggregate report (RFC 7489 §7.2)
  # as an XML attachment, so the dmarc-reports mailbox has something to parse
  # and the report summary view has real data to render.
  def build_dmarc_raw(from:, to:, subject:, body:)
    <<~EOM
      From: #{from}
      To: #{to}
      Subject: #{subject}
      Content-Type: multipart/mixed; boundary=MIX

      --MIX
      Content-Type: text/plain

      #{body}
      --MIX
      Content-Type: application/xml; name="aggregate.xml"
      Content-Disposition: attachment; filename="aggregate.xml"
      Content-Transfer-Encoding: base64

      #{Base64.strict_encode64(dmarc_report_xml)}
      --MIX--
    EOM
  end

  def dmarc_report_xml
    starts = 1.day.ago.beginning_of_day.to_i
    ends = 1.day.ago.end_of_day.to_i

    <<~XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <feedback>
        <report_metadata>
          <org_name>google.com</org_name>
          <email>noreply-dmarc-support@google.com</email>
          <report_id>#{SecureRandom.hex(8)}</report_id>
          <date_range><begin>#{starts}</begin><end>#{ends}</end></date_range>
        </report_metadata>
        <policy_published>
          <domain>#{DEV_DOMAIN_NAME}</domain>
          <adkim>r</adkim>
          <aspf>r</aspf>
          <p>reject</p>
          <sp>reject</sp>
          <pct>100</pct>
        </policy_published>
        <record>
          <row>
            <source_ip>203.0.113.42</source_ip>
            <count>128</count>
            <policy_evaluated>
              <disposition>none</disposition>
              <dkim>pass</dkim>
              <spf>pass</spf>
            </policy_evaluated>
          </row>
          <identifiers><header_from>#{DEV_DOMAIN_NAME}</header_from></identifiers>
        </record>
        <record>
          <row>
            <source_ip>198.51.100.7</source_ip>
            <count>3</count>
            <policy_evaluated>
              <disposition>quarantine</disposition>
              <dkim>fail</dkim>
              <spf>pass</spf>
              <reason><type>other</type><comment>looks forwarded</comment></reason>
            </policy_evaluated>
          </row>
          <identifiers><header_from>#{DEV_DOMAIN_NAME}</header_from></identifiers>
        </record>
        <record>
          <row>
            <source_ip>192.0.2.99</source_ip>
            <count>1</count>
            <policy_evaluated>
              <disposition>reject</disposition>
              <dkim>fail</dkim>
              <spf>fail</spf>
            </policy_evaluated>
          </row>
          <identifiers><header_from>#{DEV_DOMAIN_NAME}</header_from></identifiers>
        </record>
      </feedback>
    XML
  end

  # A long, multi-paragraph HTML body, tall enough to overflow the collapsed
  # email preview so the mail log exercises the "show full email" expansion.
  def long_html_body(intro)
    paragraphs = Array.new(18) do |i|
      "<p>Paragraph #{i + 1}: Lorem ipsum dolor sit amet, consectetur " \
        "adipiscing elit, sed do eiusmod tempor incididunt ut labore et " \
        "dolore magna aliqua. Ut enim ad minim veniam, quis nostrud " \
        "exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p>"
    end
    "<h2>#{intro}</h2>#{paragraphs.join}"
  end

  # A 1×1 transparent PNG, base64-encoded, used as the inline image.
  def seed_inline_png
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  end

  # Seed accounts
  seed_account "dev"
end
