require "test_helper"

class MailpiecesHelperTest < ActionView::TestCase
  test "a reply loses the code shown beside it, keeping its enhanced status" do
    assert_equal "4.7.1 Greylisted, try later", smtp_reply_after_code(attempt("451", "451 4.7.1 Greylisted, try later"))
    assert_equal "2.0.0 OK", smtp_reply_after_code(attempt("250", "250-2.0.0 OK"))
    assert_equal "", smtp_reply_after_code(attempt("250", "250"))
  end

  test "a reply that does not start with its code is left whole" do
    assert_equal "Connection refused", smtp_reply_after_code(attempt("421", "Connection refused"))
    assert_equal "4510 odd reply", smtp_reply_after_code(attempt("451", "4510 odd reply"))
    assert_equal "no code at all", smtp_reply_after_code(attempt(nil, "no code at all"))
  end

  private
    def attempt(code, output)
      Delivery::Attempt.new(code: code, output: output)
    end
end
