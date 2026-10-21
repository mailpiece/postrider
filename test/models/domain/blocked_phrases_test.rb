require "test_helper"

class Domain::BlockedPhrasesTest < ActiveSupport::TestCase
  test "the list drops blank lines, strips each phrase and collapses duplicates" do
    domains(:example).update!(blocked_phrases: "  Free money \r\n\r\nfree, MONEY\r\nAct now\r\n")

    assert_equal "Free money\nAct now", domains(:example).blocked_phrases
  end

  test "an emptied list is stored as nothing at all" do
    domains(:example).update!(blocked_phrases: " \r\n ")

    assert_nil domains(:example).blocked_phrases
  end

  test "a phrase is too short once capitals, accents and punctuation are set aside" do
    assert_not domains(:example).update(blocked_phrases: "a.b!")

    assert_includes domains(:example).errors[:blocked_phrases],
      "can't hold \"a.b!\": a phrase needs at least #{Domain::MIN_PHRASE_LENGTH} characters"
  end

  test "a phrase has a ceiling" do
    assert_not domains(:example).update(blocked_phrases: "x" * (Domain::MAX_PHRASE_LENGTH + 1))

    assert_includes domains(:example).errors[:blocked_phrases], "must each be #{Domain::MAX_PHRASE_LENGTH} characters or fewer"
  end

  test "the list has a ceiling" do
    phrases = (1..Domain::MAX_PHRASES + 1).map { |number| "phrase #{number}" }

    assert_not domains(:example).update(blocked_phrases: phrases.join("\n"))

    assert_includes domains(:example).errors[:blocked_phrases], "accepts at most #{Domain::MAX_PHRASES} phrases"
  end

  test "matching ignores capitals, accents, punctuation and line breaks" do
    domains(:example).update!(blocked_phrases: "El empleado con Identificación")

    assert_equal "El empleado con Identificación",
      domains(:example).blocked_phrase_in("Hola", "EL EMPLEADO,\r\ncon   identificacion: 42")
    assert_nil domains(:example).blocked_phrase_in("El empleado sin identificación", nil)
  end

  test "a Cyrillic letter is not read as the one it resembles without its mark" do
    domains(:example).update!(blocked_phrases: "мой дом")

    assert_nil domains(:example).blocked_phrase_in("мои дом")
  end

  test "a kana phrase ending in a plain letter does not match its voiced one" do
    domains(:example).update!(blocked_phrases: "いいですか")

    assert_nil domains(:example).blocked_phrase_in("いいですが")
  end

  test "an emoji before a phrase matches with or without its variation selector" do
    domains(:example).update!(blocked_phrases: "\u26A0\uFE0F Urgente hoy")

    assert domains(:example).blocked_phrase_in("\u26A0 Urgente hoy")
    assert domains(:example).blocked_phrase_in("\u26A0\uFE0F Urgente hoy")
  end

  test "a phrase matches inside a longer word and is never read as a pattern" do
    domains(:example).update!(blocked_phrases: "c.sh\nback")

    assert_equal "back", domains(:example).blocked_phrase_in("Cashback offers")
    assert_nil domains(:example).blocked_phrase_in("cash only")
  end

  test "changing the list is traced on the domain" do
    assert_difference -> { domains(:example).events.where(action: "domain_blocked_phrases_changed").count }, 1 do
      domains(:example).update!(blocked_phrases: "free money")
    end
  end

  test "saving the list unchanged is not traced" do
    domains(:example).update!(blocked_phrases: "free money")

    assert_no_difference -> { domains(:example).events.where(action: "domain_blocked_phrases_changed").count } do
      domains(:example).update!(blocked_phrases: "free money\r\n")
    end
  end
end
