# Shadow mode: the verdict is recorded and nothing acts on it.
module InboundEmail::Scorable
  extend ActiveSupport::Concern

  SYMBOL_DETAIL_LIMIT = 100

  included do
    after_create_commit :score_later, if: -> { Relay.mailscore? }
  end

  def score_later
    InboundEmail::ScoreJob.perform_later(self)
  end

  # Mail incinerated before its turn has nothing left to score.
  def score_now
    if !scored? && raw
      result = MailScore::Client.new.check(raw, ip: remote_ip, helo: helo, hostname: remote_host,
        from: mail_from.presence || "<>", rcpt: rcpt_to, queue_id: id)

      track_event "scored", action: result.action.to_s, score: result.score, complete: result.complete?,
        symbols: result.symbols.map { |symbol| scored_symbol(symbol) }
    end
  end

  def scored?
    events.exists?(action: "inbound_email_scored")
  end

  private
    def scored_symbol(symbol)
      if symbol.detail.present? && symbol.detail.length <= SYMBOL_DETAIL_LIMIT
        [ symbol.name, symbol.weight, symbol.description, symbol.detail ]
      else
        [ symbol.name, symbol.weight, symbol.description ]
      end
    end
end
