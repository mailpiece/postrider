require "test_helper"

class SignupTest < ActiveSupport::TestCase
  test "an identity created on an empty install is not staff" do
    Account.stubs(:none?).returns(true)

    Signup.new(email_address: "operator@example.com").create_identity

    assert_not Identity.find_by(email_address: "operator@example.com").staff?
  end

  test "an email that already has an account cannot sign up again" do
    assert_not Signup.new(email_address: identities(:leo).email_address).valid?(:identity_creation)
  end

  test "an empty identity left by an abandoned signup is reused" do
    identity = Identity.create!(email_address: "abandoned@example.com")

    signup = Signup.new(email_address: identity.email_address)

    assert signup.valid?(:identity_creation)
    assert_equal identity, signup.create_identity
  end

  test "completing the first account makes its identity staff" do
    Account.stubs(:none?).returns(true)
    identity = identities(:nonstaff)

    Current.without_account do
      assert Signup.new(full_name: "Operator", identity: identity).complete
    end

    assert identity.reload.staff?
  end

  test "completing a later account is not staff" do
    identity = identities(:nonstaff)

    Current.without_account do
      assert Signup.new(full_name: "Newcomer", identity: identity).complete
    end

    assert_not identity.reload.staff?
  end
end
