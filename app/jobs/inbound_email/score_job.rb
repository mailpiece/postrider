class InboundEmail::ScoreJob < ApplicationJob
  # Unreachable is an Error too: its retry wins because Rails checks the last-declared handler first.
  discard_on MailScore::Client::Error do |job, error|
    job.logger.warn "Mailscore refused InboundEmail #{job.arguments.first.id}: #{error.message}"
  end

  retry_on MailScore::Client::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.logger.warn "Mailscore unreachable, InboundEmail #{job.arguments.first.id} left unscored: #{error.message}"
  end

  discard_on ActiveJob::DeserializationError

  def perform(inbound_email)
    inbound_email.score_now
  end
end
