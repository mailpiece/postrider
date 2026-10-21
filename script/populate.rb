require_relative "../config/environment"
require "faker"
require "active_support/testing/time_helpers"

include ActiveSupport::Testing::TimeHelpers

abort "populate.rb is just for development!" unless Rails.env.development?

ACCOUNT        = Account.first || abort("No account yet — run bin/rails db:seed first.")
INBOUND_COUNT  = ARGV.first&.to_i || 5_000
OUTBOUND_COUNT = ARGV.second&.to_i || 5_000
WINDOW         = (ARGV.third&.to_i || 14).days

INBOUND_OUTCOMES  = %i[ delivered delivered delivered delivered delivered delivered delivered failed bounced ].freeze
OUTBOUND_OUTCOMES = %i[ delivered delivered delivered delivered delivered delivered delivered deferred bounced exhausted suppressed ].freeze

INBOUND_IN_FLIGHT  = %i[ pending processing ].freeze
OUTBOUND_IN_FLIGHT = %i[ queued deferred ].freeze
IN_FLIGHT_WINDOW   = 1.hour

ASYNC_BOUNCE_RATE = 0.02

FAN_OUT = [ 1, 1, 1, 1, 1, 2, 3 ].freeze

MAILBOXES        = %w[ support sales hello billing help team press ].freeze
TAGS             = %w[ transactional marketing digest receipt notification ].freeze
FAILURE_REASONS  = %w[ abandoned unparseable oversized ].freeze
PROGRESS_EVERY   = 25

SUBJECTS = [
  -> { "Re: #{Faker::Company.catch_phrase}" },
  -> { "Invoice ##{Faker::Number.number(digits: 6)} is ready" },
  -> { "Your order ##{Faker::Number.number(digits: 7)} has shipped" },
  -> { "Question about #{Faker::Commerce.product_name}" },
  -> { "#{Faker::Company.name} — partnership inquiry" },
  -> { "Password reset for #{Faker::Internet.username}" },
  -> { "Trouble with #{Faker::App.name}" },
  -> { "Welcome to #{Faker::App.name}" },
  -> { "Your weekly digest is here" },
  -> { "Re: #{Faker::Lorem.sentence(word_count: 4).chomp(".")}" }
].freeze

class DiscardingQueueAdapter
  def enqueue(*) = nil
  def enqueue_at(*) = nil
end

def populate
  puts "Populating account #{ACCOUNT.external_account_id} (#{ACCOUNT.name}) with #{INBOUND_COUNT} inbound " \
    "and #{OUTBOUND_COUNT} outbound over the last #{WINDOW.inspect}"

  Current.with_account(ACCOUNT) do
    without_enqueuing_jobs do
      with_progress(timeline(INBOUND_COUNT)) { |at| create_inbound(at:) }
      with_progress(timeline(OUTBOUND_COUNT)) { |at| create_outbound(at:) }
    end

    report
  end
end

def without_enqueuing_jobs
  adapter = ActiveJob::Base.queue_adapter
  ActiveJob::Base.queue_adapter = DiscardingQueueAdapter.new
  yield
ensure
  ActiveJob::Base.queue_adapter = adapter
end

def with_progress(times)
  times.each_with_index do |at, index|
    yield at
    print "." if ((index + 1) % PROGRESS_EVERY).zero?
  end

  puts
end

def timeline(count)
  Array.new(count) { WINDOW.ago + rand(WINDOW.to_i) }.sort
end

def create_inbound(at:)
  status = outcome(INBOUND_OUTCOMES, INBOUND_IN_FLIGHT, at)

  travel_to at do
    name = Faker::Name.name
    from = Faker::Internet.email(name:)
    to   = "#{MAILBOXES.sample}@#{domains.sample}"
    raw  = build_raw(from:, to:, subject: subject_line, body: body_signed_by(name))

    receive InboundEmail.create!(mail_from: from, rcpt_to: to, raw:, digest: content_digest(from, raw)), status:
  end
end

def receive(inbound, status:)
  case status
  when :delivered
    inbound.update!(**verdicts)
    inbound.track_event inbound.to_bounce_address? ? "bounce_received" : "received", rcpt_to: inbound.rcpt_to
    inbound.update! status: :delivered, forwarded_at: Time.current
  when :bounced
    inbound.discard reason: "unregistered_recipient"
  when :failed
    inbound.fail_permanently reason: FAILURE_REASONS.sample
  when :processing
    inbound.processing!
  end
end

# No authentication_results: nothing reads a bulk record's results header, and db/seeds.rb
# already stands one up for inspecting the API.
def verdicts
  dmarc = %w[ pass pass pass pass fail none ].sample

  {
    spf: %w[ pass pass pass pass softfail fail none ].sample,
    dkim: %w[ pass pass pass pass fail none ].sample,
    dmarc:,
    dmarc_policy: %w[ none quarantine reject ].sample,
    from_aligned: dmarc == "pass"
  }
end

def create_outbound(at:)
  travel_to at do
    from       = "#{MAILBOXES.sample}@#{domains.sample}"
    recipients = Array.new(FAN_OUT.sample) { Faker::Internet.email(name: Faker::Name.name) }
    raw        = build_raw(from:, to: recipients.join(", "), subject: subject_line, body: body_signed_by(Faker::Name.name))

    message = Message.create!(mail_from: from, raw:, tags: [ TAGS.sample ])
    message.deliveries.create_for(recipients).each do |delivery|
      deliver delivery, status: outcome(OUTBOUND_OUTCOMES, OUTBOUND_IN_FLIGHT, at)
    end
  end
end

def deliver(delivery, status:)
  case status
  when :delivered
    attempt delivery, code: "250", output: "2.0.0 Ok: queued as #{SecureRandom.hex(5).upcase}"
    delivery.delivered!
    delivery.track_event "delivered", rcpt_to: delivery.rcpt_to
    bounce_afterwards delivery if rand < ASYNC_BOUNCE_RATE
  when :bounced
    output = "5.1.1 <#{delivery.rcpt_to}>: Recipient address rejected: User unknown in virtual mailbox table"
    attempt delivery, code: "550", output:
    delivery.bounced!
    suppress delivery
    delivery.track_event "bounced", rcpt_to: delivery.rcpt_to, smtp_code: "550", smtp_output: output
  when :deferred
    output = "4.3.2 Service currently unavailable, try again later"
    attempt delivery, code: "451", output:
    delivery.deferred!
    delivery.track_event "deferred", rcpt_to: delivery.rcpt_to, smtp_code: "451", smtp_output: output
  when :exhausted
    attempt delivery, code: nil, output: "Connection timed out"
    delivery.exhaust
  when :suppressed
    suppress delivery
    delivery.suppressed!
    delivery.track_event "failed", rcpt_to: delivery.rcpt_to, reason: "suppressed"
  end
end

def attempt(delivery, code:, output:)
  delivery.attempts.create! code:, output:, mx_host: mx_host_for(delivery.rcpt_to),
    transcript: transcript(delivery, code:, output:)
end

def mx_host_for(address)
  "mx#{rand(1..2)}.#{address.split("@").last}"
end

def transcript(delivery, code:, output:)
  <<~TRANSCRIPT
    >>> MAIL FROM:<#{delivery.mail_from}>
    <<< 250 2.1.0 Ok
    >>> RCPT TO:<#{delivery.rcpt_to}>
    <<< 250 2.1.5 Ok
    >>> DATA
    <<< #{[ code, output ].compact.join(" ")}
  TRANSCRIPT
end

def bounce_afterwards(delivery)
  delivery.record_async_bounce dsn_raw: DsnReport.new(rcpt_to: delivery.rcpt_to, code: "550",
    diagnostic: "5.2.1 The email account that you tried to reach is disabled").to_raw
end

def suppress(delivery)
  delivery.account.suppressions.find_or_create_by!(address: delivery.rcpt_to) do |suppression|
    suppression.reason = "hard bounce"
  end
end

def outcome(terminal, in_flight, at)
  if at > IN_FLIGHT_WINDOW.ago
    (terminal + in_flight).sample
  else
    terminal.sample
  end
end

def domains
  @domains ||= ACCOUNT.domains.pluck(:name).presence || %w[ hello.example ]
end

def subject_line
  SUBJECTS.sample.call
end

def body_signed_by(name)
  <<~BODY
    Hi there,

    #{Faker::Lorem.paragraph(sentence_count: rand(2..4))}

    #{Faker::Lorem.paragraph(sentence_count: rand(1..3))}

    Thanks,
    #{name}
  BODY
end

def build_raw(from:, to:, subject:, body:)
  [
    "From: #{from}",
    "To: #{to}",
    "Subject: #{subject}",
    "Date: #{Time.current.rfc2822}",
    "Message-ID: <#{SecureRandom.uuid}@#{from.split("@").last}>",
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "",
    body
  ].join("\r\n")
end

def content_digest(mail_from, raw)
  Digest::SHA256.new.update("#{mail_from}\n").update(raw).hexdigest
end

def report
  postmaster = Postmaster.new(ACCOUNT.reload)

  puts "Account #{ACCOUNT.external_account_id} now holds:"
  puts "  #{ACCOUNT.mailpieces.count} mailpieces — #{ACCOUNT.inbound_emails.count} inbound, #{ACCOUNT.deliveries.count} outbound"
  puts "  #{ACCOUNT.messages.count} messages, #{ACCOUNT.events.count} events, #{ACCOUNT.suppressions_count} suppressions"
  puts "  last 24h: #{postmaster.received} received, #{postmaster.delivered} delivered, #{postmaster.failed} failed " \
    "(#{postmaster.bounce_rate}% bounce rate), #{postmaster.deferred_backlog} deferred, #{postmaster.skipped} skipped"
  puts "  mail log: #{ACCOUNT.slug}/mailpieces"
end

populate
