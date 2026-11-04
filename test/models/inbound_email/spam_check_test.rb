require "test_helper"

class InboundEmail::SpamCheckTest < ActiveSupport::TestCase
  test "a passing check gives only its score, since the stamp says what passed" do
    check = spam_check "no_action", -1.8, [ "SPF_PASS", -0.2, "SPF passed", "example.com" ],
      [ "DKIM_PASS", -0.1, "DKIM signature valid", "example.com" ], [ "DMARC_PASS", -0.5, "DMARC passed", "example.com" ],
      [ "ARC_PASS", -1.0, "ARC chain valid" ]

    assert_equal "Spam check: no action, score −1.8.", check.sentence
  end

  test "a passing check leaves out other credits" do
    check = spam_check "no_action", -3.2, [ "SPF_PASS", -0.2, "SPF passed" ], [ "BAYES_HAM", -3.0, "Learned filter says not spam" ]

    assert_equal "Spam check: no action, score −3.2.", check.sentence
  end

  test "a flagged check lists its problems, worst first" do
    check = spam_check "reject", 16.7, [ "SPF_PASS", -0.2, "SPF passed", "mailer.example" ],
      [ "BAYES_HAM", -3.0, "Learned filter says not spam" ], [ "DATE_MISSING", 1.0, "No Date header" ],
      [ "MESSAGE_ID_MISSING", 2.5, "No Message-ID header" ], [ "LINK_TO_IP_ADDRESS", 1.0, "Link to an IP address", "198.51.100.4" ],
      [ "REVERSE_DNS_NONE", 2.0, "No reverse DNS for the sending server" ], [ "LINK_ONLY", 2.2, "The message is only a link" ],
      [ "DMARC_FAIL_REJECT_POLICY", 5.5, "DMARC failed under a reject policy", "paypal.com p=reject" ]

    assert_equal "Spam check: would reject, score 16.7. " \
      "DMARC failed under a reject policy (paypal.com); no Message-ID header; the message is only a link; " \
      "no reverse DNS for the sending server; no Date header; link to an IP address.", check.sentence
  end

  test "a DMARC failure with no detail names no domain" do
    check = spam_check "soft_reject", 5.5, [ "DMARC_FAIL_QUARANTINE_POLICY", 5.5, "DMARC failed under a quarantine policy" ]

    assert_equal "Spam check: would defer it, score 5.5. DMARC failed under a quarantine policy.", check.sentence
  end

  test "a symbol with no weight is left out" do
    check = spam_check "no_action", 0.0, [ "DMARC_NONE", 0.0, "No DMARC record" ], [ "GREYLISTED", 0.0, nil, "pass" ]

    assert_equal "Spam check: no action, score 0.0.", check.sentence
  end

  test "a symbol with no description is named in words" do
    check = spam_check "add_header", 7.0, [ "CLIENT_SPAMHAUS_SPAM_SOURCE", 4.0, nil, "127.0.0.2" ],
      [ "SUBJECT_ALL_CAPS", 3.0, "Subject in capitals" ]

    assert_equal "Spam check: would add a spam header, score 7.0. Client spamhaus spam source; subject in capitals.", check.sentence
  end

  test "an action with no phrase is given in words" do
    assert_equal "Spam check: would quarantine it, score 9.0.", spam_check("quarantine_it", 9.0).sentence
  end

  test "the outcome and score read on their own" do
    check = spam_check "reject", 9.44

    assert_equal "would reject", check.outcome
    assert_equal "9.4", check.formatted_score
    assert_equal "no action", spam_check("no_action", -1.8).outcome
    assert_equal "−1.8", spam_check("no_action", -1.8).formatted_score
  end

  test "flagged unless the check would take no action" do
    assert spam_check("greylist", 4.0).flagged?
    assert_not spam_check("no_action", 1.0).flagged?
  end

  private
    def spam_check(action, score, *symbols)
      InboundEmail::SpamCheck.new("action" => action, "score" => score, "complete" => true, "symbols" => symbols)
    end
end
