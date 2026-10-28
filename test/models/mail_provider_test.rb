require "test_helper"

class MailProviderTest < ActiveSupport::TestCase
  test "domains on a provider's servers share it" do
    assert_equal "outlook", MailProvider.for("hotmail-com.olc.protection.outlook.com")
    assert_equal "outlook", MailProvider.for("eur.olc.protection.outlook.com")
    assert_equal "yahoo", MailProvider.for("mta5.am0.yahoodns.net")
    assert_equal "yahoo", MailProvider.for("mx-aol.mail.gm0.yahoodns.net")
    assert_equal "gmail", MailProvider.for("gmail-smtp-in.l.google.com")
    assert_equal "gmail", MailProvider.for("aspmx.l.google.com")
    assert_equal "gmail", MailProvider.for("aspmx2.googlemail.com")
  end

  test "a tenant's own servers are no provider" do
    assert_nil MailProvider.for("contoso-com.mail.protection.outlook.com")
    assert_nil MailProvider.for("mx1.example.com")
    assert_nil MailProvider.for("notgoogle.com")
    assert_nil MailProvider.for(nil)
  end
end
