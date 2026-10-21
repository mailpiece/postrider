account = dev_account

Current.with_account(account) do
  reset_mail

  # Inbound: catch-all mail landing on the account's domains, spanning every status.
  create_inbound from: "alice@customer.com",  to: "support@hello.example",
    subject: "Can't reset my password",
    body: "Hi team, the reset link in your email 404s for me. Can you help?"

  create_inbound from: "bob@bigcorp.io",      to: "sales@hello.example",
    subject: "Interested in the enterprise plan",
    body: "We're a team of 200 and would love a demo of the enterprise tier."

  create_inbound from: "carol@example.org",   to: "hello@hello.example",
    subject: "Re: Your invoice for June",
    body: "Thanks, payment has been sent. Appreciate the quick turnaround."

  create_inbound from: "dan@newsletter.net",  to: "press@hello.example",
    subject: "Feature request: dark mode",
    body: "Any chance dark mode is on the roadmap? It's the one thing I miss."

  create_inbound from: "eve@partner.co",      to: "billing@hello.example",
    subject: "Updated W-9 attached",
    body: "Please find our updated tax form for your records.",
    rich: true

  create_inbound from: "frank@acme.dev",      to: "support@hello.example",
    subject: "App crashes on upload",
    body: "Uploading a 12MB PDF crashes the tab every time on Safari.",
    status: :failed

  # The authentication badges the mail log shows: a sender whose own DMARC fails is
  # what a spoofed one looks like; the unauthenticated one at the end is what the
  # log looks like when mailauth never got an answer.
  create_inbound from: "grace@spammy.biz",    to: "unknown@hello.example",
    subject: "You've WON a prize!!!",
    body: "Click here to claim your reward before it expires.",
    status: :bounced,
    auth: :spoofed

  create_inbound from: "mallory@bulk.marketing", to: "press@hello.example",
    subject: "Last chance — 80% off everything",
    body: "Our biggest sale of the year ends tonight. Don't miss out!",
    arc: "pass", arc_sealer: "lists.mailinglist.example"

  create_inbound from: "heidi@startup.app",   to: "hello@hello.example",
    subject: "Quick question about the API",
    body: "Does the outbound API support idempotency keys?",
    status: :pending,
    auth: nil

  create_inbound from: "ivan@agency.studio",  to: "sales@hello.example",
    subject: "Proposal for Q3 campaign",
    body: "Attaching our proposal — happy to walk you through it this week.",
    status: :processing,
    auth: nil, spf: "pass", dkim: "fail", dmarc: "fail"

  # Long HTML bodies that overflow the collapsed preview, for testing the
  # "show full email" expansion in the mail log.
  create_inbound from: "judy@longwind.com",   to: "support@hello.example",
    subject: "Detailed bug report with lots of context",
    body: long_html_body("Here's everything I've tried so far"),
    rich: true,
    auth: nil

  # A DMARC aggregate report, landing on the reserved dmarc-reports mailbox the
  # domain's DMARC record already publishes as its rua= address.
  create_inbound from: "noreply-dmarc-support@google.com", to: "dmarc-reports@hello.example",
    subject: "Report domain: hello.example Submitter: google.com Report-ID: dev-seed",
    body: "This is an aggregate report from google.com.",
    dmarc: true

  # Outbound: authenticated submissions fanned out to recipients, spanning every status.
  create_outbound from: "noreply@hello.example", to: "alice@customer.com",
    subject: "Your password reset link",
    body: "Use the link below to set a new password. It expires in one hour.",
    attempts: [
      smtp_attempt(mx_host: "mx.customer.com", code: "421", output: "421 4.3.0 Temporary failure, try again later",
        ago: 1.hour.ago,
        transcript: <<~TXT),
          Connection opened: 203.0.113.12:25
          -> "220 mx.customer.com ESMTP Postfix\\r\\n"
          <- "EHLO mx.app.postrider.dev\\r\\n"
          -> "250-mx.customer.com\\r\\n"
          -> "250-PIPELINING\\r\\n"
          -> "250-STARTTLS\\r\\n"
          -> "250 CHUNKING\\r\\n"
          <- "STARTTLS\\r\\n"
          -> "421 4.3.0 Temporary failure, try again later\\r\\n"
        TXT
      smtp_attempt(mx_host: "mx.customer.com", code: "250", output: "250 2.0.0 Ok: queued as 9E7D8101363",
        ago: Time.current,
        transcript: <<~TXT)
          Connection opened: 203.0.113.12:25
          -> "220 mx.customer.com ESMTP Postfix\\r\\n"
          <- "EHLO mx.app.postrider.dev\\r\\n"
          -> "250-mx.customer.com\\r\\n"
          -> "250-PIPELINING\\r\\n"
          -> "250-STARTTLS\\r\\n"
          -> "250-ENHANCEDSTATUSCODES\\r\\n"
          -> "250 CHUNKING\\r\\n"
          <- "STARTTLS\\r\\n"
          -> "220 2.0.0 Ready to start TLS\\r\\n"
          TLS connection started
          <- "EHLO mx.app.postrider.dev\\r\\n"
          -> "250-mx.customer.com\\r\\n"
          -> "250-PIPELINING\\r\\n"
          -> "250-ENHANCEDSTATUSCODES\\r\\n"
          -> "250 CHUNKING\\r\\n"
          <- "MAIL FROM:<bounces+seed@mx.app.postrider.dev>\\r\\n"
          -> "250 2.1.0 Ok\\r\\n"
          <- "RCPT TO:<alice@customer.com>\\r\\n"
          -> "250 2.1.5 Ok\\r\\n"
          <- "DATA\\r\\n"
          -> "354 End data with <CR><LF>.<CR><LF>\\r\\n"
          writing message from String
          wrote 412 bytes
          -> "250 2.0.0 Ok: queued as 9E7D8101363\\r\\n"
          <- "QUIT\\r\\n"
          -> "221 2.0.0 Bye\\r\\n"
        TXT
    ],
    events: [
      [ "deferred", { smtp_code: "421", smtp_output: "421 4.3.0 Temporary failure, try again later" } ],
      [ "delivered", {} ]
    ]

  create_outbound from: "sales@hello.example",   to: "bob@bigcorp.io",
    subject: "Enterprise demo — pick a time",
    body: "Great to hear from you! Here are a few slots for a walkthrough."

  create_outbound from: "billing@hello.example", to: "carol@example.org",
    subject: "Receipt for your June invoice",
    body: "Thanks for your payment. Your receipt is attached.",
    rich: true

  create_outbound from: "digest@hello.example",  to: "slow-server@laggard.net",
    subject: "Your weekly digest",
    body: "Here's what happened in your groups this week.",
    status: :deferred,
    attempts: [
      smtp_attempt(mx_host: "mx1.laggard.net", code: nil, output: "Connection timed out - user=<nil> host=mx1.laggard.net",
        ago: 3.hours.ago,
        transcript: <<~TXT),
          Connection opened: 198.51.100.44:25
          -> "220 mx1.laggard.net ESMTP\\r\\n"
          <- "EHLO mx.app.postrider.dev\\r\\n"
        TXT
      smtp_attempt(mx_host: "mx1.laggard.net", code: "450", output: "450 4.7.1 Greylisted, try again in a few minutes",
        ago: 1.hour.ago,
        transcript: <<~TXT)
          Connection opened: 198.51.100.44:25
          -> "220 mx1.laggard.net ESMTP\\r\\n"
          <- "EHLO mx.app.postrider.dev\\r\\n"
          -> "250-mx1.laggard.net\\r\\n"
          -> "250-PIPELINING\\r\\n"
          -> "250 8BITMIME\\r\\n"
          <- "MAIL FROM:<bounces+seed@mx.app.postrider.dev>\\r\\n"
          -> "250 2.1.0 Ok\\r\\n"
          <- "RCPT TO:<slow-server@laggard.net>\\r\\n"
          -> "450 4.7.1 Greylisted, try again in a few minutes\\r\\n"
          <- "QUIT\\r\\n"
          -> "221 2.0.0 Bye\\r\\n"
        TXT
    ],
    events: [
      [ "deferred", { smtp_code: nil, smtp_output: "Connection timed out - user=<nil> host=mx1.laggard.net" } ],
      [ "deferred", { smtp_code: "450", smtp_output: "450 4.7.1 Greylisted, try again in a few minutes" } ]
    ]

  create_outbound from: "noreply@hello.example", to: "typo@nonexistent.invalid",
    subject: "Welcome aboard",
    body: "Thanks for signing up! Here's how to get started.",
    status: :bounced,
    attempts: [
      smtp_attempt(mx_host: "mx.nonexistent.invalid", code: "550", output: "550 5.1.1 The email account that you tried to reach does not exist",
        ago: 30.minutes.ago,
        transcript: <<~TXT)
          Connection opened: 192.0.2.55:25
          -> "220 mx.nonexistent.invalid ESMTP\\r\\n"
          <- "EHLO mx.app.postrider.dev\\r\\n"
          -> "250 mx.nonexistent.invalid\\r\\n"
          <- "MAIL FROM:<bounces+seed@mx.app.postrider.dev>\\r\\n"
          -> "250 2.1.0 Ok\\r\\n"
          <- "RCPT TO:<typo@nonexistent.invalid>\\r\\n"
          -> "550 5.1.1 The email account that you tried to reach does not exist\\r\\n"
          <- "QUIT\\r\\n"
          -> "221 2.0.0 Bye\\r\\n"
        TXT
    ],
    events: [
      [ "bounced", { smtp_code: "550", smtp_output: "550 5.1.1 The email account that you tried to reach does not exist" } ]
    ]

  create_outbound from: "alerts@hello.example",  to: "abandoned@deadhost.example",
    subject: "Service alert",
    body: "We noticed unusual activity on your account.",
    status: :exhausted,
    events: [ [ "failed", { reason: "exhausted" } ] ]

  create_outbound from: "marketing@hello.example", to: "unsubscribed@customer.com",
    subject: "New features you'll love",
    body: "We shipped a bunch of improvements this month.",
    status: :suppressed,
    events: [ [ "failed", { reason: "suppressed" } ] ]

  create_outbound from: "support@hello.example", to: "heidi@startup.app",
    subject: "Re: Quick question about the API",
    body: "Yes! Pass an Idempotency-Key header and we'll dedupe retries.",
    status: :queued

  create_outbound from: "support@hello.example", to: "judy@longwind.com",
    subject: "Re: Detailed bug report with lots of context",
    body: long_html_body("Thanks for the detail — here's our full analysis"),
    rich: true

  # Bulk volume: 200 inbound and 200 outbound to fill out the mail log, with
  # statuses weighted toward the happy path the way real traffic is.
  people   = %w[ alice bob carol dan eve frank grace heidi ivan judy mallory olivia peggy trent victor walter ]
  domains  = %w[ customer.com bigcorp.io example.org newsletter.net partner.co acme.dev startup.app agency.studio ]
  mailboxes = %w[ support sales hello press billing help team ]
  subjects = [
    "Question about my account", "Follow-up on our call", "Re: Your invoice",
    "Trouble logging in", "Feature request", "Bug report", "Partnership inquiry",
    "Renewal reminder", "Thanks for the help", "Onboarding question"
  ]
  inbound_statuses  = %i[ delivered delivered delivered delivered failed bounced pending processing ]
  outbound_statuses = %i[ delivered delivered delivered delivered deferred bounced exhausted suppressed queued ]

  # Weighted the way a real catch-all looks: mostly authenticated, a few spoofed,
  # and a few mailauth never answered for.
  inbound_verdicts = %i[ authenticated authenticated authenticated spoofed unauthenticated ]

  30.times do |i|
    person = people[i % people.size]
    domain = domains[i % domains.size]
    box    = mailboxes[i % mailboxes.size]
    subject = subjects[i % subjects.size]

    rich = (i % 10).zero?

    sender = "#{person}@#{domain}"

    create_inbound from: sender, to: "#{box}@hello.example",
      subject: "#{subject} ##{i + 1}",
      body: "Automated seed message ##{i + 1} from #{sender}.",
      status: inbound_statuses[i % inbound_statuses.size],
      rich: rich,
      auth: inbound_verdicts[i % inbound_verdicts.size]

    create_outbound from: "#{box}@hello.example", to: "#{person}@#{domain}",
      subject: "Re: #{subject} ##{i + 1}",
      body: "Automated seed reply ##{i + 1} to #{person}@#{domain}.",
      status: outbound_statuses[i % outbound_statuses.size],
      rich: rich
  end

  # Screening: every sender a domain hears from lands in its contact ledger. Approved
  # contacts have their mail forwarded, denied ones have it held — which is what
  # /contacts and /contacts/denied each list.
  [ [ "alice@customer.com", "Alice Nguyen" ], [ "bob@bigcorp.io", "Bob Iyer" ],
    [ "carol@example.org", "Carol Diaz" ], [ "eve@partner.co", "Eve Okafor" ] ].each do |email, name|
    dev_domain.contacts.create!(email:, name:, decision: :approved)
  end

  held_mail = {
    [ "recruiter@talent.agency", "Riley Recruiter" ] => [
      [ "An exciting opportunity for you", "I came across your profile and thought of a role you'd love." ],
      [ "Following up on my last note", "Just floating this back to the top of your inbox." ]
    ],
    [ "deals@shopping.example", "Shopping Deals" ] => [
      [ "48 hours only: everything must go", "Our warehouse is overflowing and the discounts show it." ]
    ],
    [ "no-reply@social.example", nil ] => [
      [ "You have 3 new notifications", "See what you missed while you were away." ],
      [ "Someone mentioned you in a comment", "Tap through to read the thread." ],
      [ "Your weekly summary is ready", "Here's how last week went." ]
    ],
    [ "newsletter@industry.press", "Industry Press" ] => [
      [ "This week in email infrastructure", "SPF alignment, BIMI adoption, and one very odd bounce loop." ]
    ]
  }

  held_mail.each do |(email, name), mail|
    contact = dev_domain.contacts.create!(email:, name:)

    mail.each do |subject, body|
      create_inbound from: email, to: "hello@hello.example", subject:, body:,
        status: :held, contact:
    end
  end

  # A webhook with a mix of delivery outcomes, so its "Recent deliveries" list has
  # real activity. insert_all bypasses Webhook::Delivery's after_create_commit
  # callback — seed data should never fire a real HTTP request. Destroyed and
  # recreated each run, the same as the mail reset_mail wipes and rebuilds.
  dev_domain.webhooks.where(name: "Order events").destroy_all
  webhook = dev_domain.webhooks.create!(name: "Order events", url: "https://example.com/webhooks/postrider",
    subscribed_actions: %w[ inbound_email_received delivery_delivered delivery_bounced delivery_deferred delivery_failed ])

  webhook_events = dev_domain.events.order(created_at: :desc).first(4)
  webhook_states = [ :completed, :completed, :completed, :pending ]
  webhook_responses = [ { code: 200 }, { code: 200 }, { error: "connection_timeout" }, nil ]

  Webhook::Delivery.insert_all!(
    webhook_events.each_with_index.map do |event, i|
      {
        id: ActiveRecord::Type::Uuid.generate,
        account_id: account.id,
        webhook_id: webhook.id,
        event_id: event.id,
        state: webhook_states[i],
        response: webhook_responses[i],
        created_at: Time.current - i.minutes,
        updated_at: Time.current - i.minutes
      }
    end
  )

  puts "  → account #{account.external_account_id}: " \
    "#{Current.account.inbound_emails.count} inbound, #{Current.account.deliveries.count} outbound, " \
    "#{Current.account.contacts.count} contacts"
end
