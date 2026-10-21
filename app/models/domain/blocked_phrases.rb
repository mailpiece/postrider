module Domain::BlockedPhrases
  extend ActiveSupport::Concern

  MIN_PHRASE_LENGTH = 4
  MAX_PHRASE_LENGTH = 200
  MAX_PHRASES = 100

  included do
    normalizes :blocked_phrases, with: ->(value) {
      value.lines.map(&:strip).reject(&:blank?).uniq { |phrase| normalize_phrase(phrase) }.join("\n").presence
    }

    validate :blocked_phrases_within_limits, if: :blocked_phrases_changed?

    after_update :track_blocked_phrases_change, if: :saved_change_to_blocked_phrases?
  end

  class_methods do
    # Only accents on Latin letters go: in other scripts a mark makes a different letter.
    def normalize_phrase(text)
      text.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        .unicode_normalize(:nfkd).gsub(/(\p{Latin})[\u0300-\u036F]+/, "\\1").unicode_normalize(:nfc).downcase(:fold)
        .gsub(/(?:[^\p{L}\p{N}\p{M}]\p{M}*)+/, " ").sub(/\A\p{M}+/, "").strip
    end
  end

  def blocked_phrase_list
    blocked_phrases.to_s.lines(chomp: true)
  end

  def blocked_phrase_in(*texts)
    normalized_texts = texts.compact.map { |text| self.class.normalize_phrase(text) }

    blocked_phrase_list.find do |phrase|
      normalized_phrase = self.class.normalize_phrase(phrase)
      normalized_phrase.present? && normalized_texts.any? { |text| text.include?(normalized_phrase) }
    end
  end

  private
    def blocked_phrases_within_limits
      if blocked_phrase_list.size > MAX_PHRASES
        errors.add(:blocked_phrases, "accepts at most #{MAX_PHRASES} phrases")
      elsif blocked_phrase_list.any? { |phrase| phrase.length > MAX_PHRASE_LENGTH }
        errors.add(:blocked_phrases, "must each be #{MAX_PHRASE_LENGTH} characters or fewer")
      elsif short_phrase = blocked_phrase_list.find { |phrase| self.class.normalize_phrase(phrase).length < MIN_PHRASE_LENGTH }
        errors.add(:blocked_phrases, "can't hold \"#{short_phrase}\": a phrase needs at least #{MIN_PHRASE_LENGTH} characters")
      end
    end

    def track_blocked_phrases_change
      track_event "blocked_phrases_changed"
    end
end
