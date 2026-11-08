module InboundEmail::Scorable
  extend ActiveSupport::Concern

  SYMBOL_DETAIL_LIMIT = 100

  # Mail is not held up for a scorer that is down or slow: the job scores it once it answers.
  def score
    if Relay.mailscore?
      score_with MailScore::Client.new(read_timeout: 4, deadline: 5)
    end
  rescue MailScore::Client::Error
    score_later
  end

  def score_later
    InboundEmail::ScoreJob.perform_later(self)
  end

  def score_now
    score_with MailScore::Client.new
  end

  def scored?
    events.exists?(action: "inbound_email_scored")
  end

  def spam_check
    if event = events.find_by(action: "inbound_email_scored")
      InboundEmail::SpamCheck.new(event.particulars)
    end
  end

  private
    # Mail incinerated before its turn has nothing left to score.
    def score_with(client)
      if !scored? && raw
        result = client.check(raw, ip: remote_ip, helo: helo, hostname: remote_host,
          from: mail_from.presence || "<>", rcpt: rcpt_to, queue_id: id)

        track_event "scored", action: result.action.to_s, score: result.score, complete: result.complete?,
          symbols: result.symbols.map { |symbol| scored_symbol(symbol) }
      end
    end

    def scored_symbol(symbol)
      if symbol.detail.present? && symbol.detail.length <= SYMBOL_DETAIL_LIMIT
        [ symbol.name, symbol.weight, symbol.description, symbol.detail ]
      else
        [ symbol.name, symbol.weight, symbol.description ]
      end
    end
end
