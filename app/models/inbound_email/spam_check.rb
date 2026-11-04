# A spam verdict told in words, from an inbound_email_scored event's particulars.
class InboundEmail::SpamCheck
  ACTION_PHRASES = {
    "add_header" => "add a spam header",
    "rewrite_subject" => "mark the subject",
    "greylist" => "greylist it",
    "soft_reject" => "defer it",
    "reject" => "reject"
  }.freeze

  attr_reader :action, :score

  def initialize(particulars)
    @action = particulars["action"]
    @score = particulars["score"]
    @symbols = particulars["symbols"].to_a.map { |name, weight, description, detail| { name:, weight:, description:, detail: } }
  end

  # A flagged verdict lists only its problems.
  def sentence
    [ "Spam check: #{outcome}, score #{formatted_score}.", problems_sentence, (passes_sentence unless flagged?) ].compact.join(" ")
  end

  def flagged?
    action != "no_action"
  end

  # Shadow mode: nothing acts on the verdict, so it says what would have happened.
  def outcome
    if flagged?
      "would #{ACTION_PHRASES.fetch(action) { action.to_s.tr("_", " ") }}"
    else
      "no action"
    end
  end

  def formatted_score
    ActiveSupport::NumberHelper.number_to_rounded(score, precision: 1).sub("-", "−")
  end

  private
    def problems_sentence
      problems = @symbols.select { |symbol| symbol[:weight].to_f.positive? && !pass?(symbol) }
      phrases_sentence problems.sort_by.with_index { |symbol, index| [ -symbol[:weight].to_f, index ] }
    end

    # The SPF, DKIM, DMARC and ARC passes read as one "… passed", then any other credit.
    def passes_sentence
      passes = @symbols.select { |symbol| pass?(symbol) }
      credits = @symbols.select { |symbol| !pass?(symbol) && symbol[:weight].to_f.negative? }
      passed = "#{passes.map { |pass| pass[:name].delete_suffix("_PASS") }.to_sentence(last_word_connector: " and ")} passed" if passes.any?

      phrases_sentence credits, leading: passed
    end

    def pass?(symbol)
      symbol[:name].end_with?("_PASS")
    end

    def phrases_sentence(symbols, leading: nil)
      phrases = [ leading, *symbols.map { |symbol| phrase(symbol) } ].compact

      "#{phrases.join("; ").upcase_first}." if phrases.any?
    end

    # mailscore's description, with a DMARC failure's domain. A name with no
    # description still says something: the name itself, in words.
    def phrase(symbol)
      [ described(symbol), failed_dmarc_domain(symbol) ].compact.join(" ")
    end

    # A first word in capitals is an acronym, so it keeps them.
    def described(symbol)
      if description = symbol[:description].presence
        description.match?(/\A[A-Z]{2,}\b/) ? description : description.downcase_first
      else
        symbol[:name].downcase.tr("_", " ")
      end
    end

    def failed_dmarc_domain(symbol)
      if symbol[:name].start_with?("DMARC_FAIL") && (domain = symbol[:detail].to_s.split.first)
        "(#{domain})"
      end
    end
end
