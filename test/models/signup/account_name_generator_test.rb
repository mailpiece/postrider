require "test_helper"

class Signup::AccountNameGeneratorTest < ActiveSupport::TestCase
  setup do
    @identity = Identity.create!(email_address: "newart.userbaum@example.com")
    @name = "Newart userbaum"
    @generator = Signup::AccountNameGenerator.new(identity: @identity, name: @name)
  end

  test "generate numbers the accounts after the first" do
    assert_equal "Newart's PostRider", @generator.generate

    join Account.create!(name: "Newart's PostRider")
    assert_equal "Newart's 2nd PostRider", @generator.generate

    join Account.create!(name: "Newart's 2nd PostRider")
    assert_equal "Newart's 3rd PostRider", @generator.generate
  end

  test "generate continues from the previous highest index" do
    join Account.create!(name: "Newart's 12th PostRider")

    assert_equal "Newart's 13th PostRider", @generator.generate
  end

  test "generate treats regex metacharacters in the name literally" do
    join Account.create!(name: "AB's PostRider")

    generator = Signup::AccountNameGenerator.new(identity: @identity, name: "A. Smith")
    assert_equal "A.'s PostRider", generator.generate
  end

  private
    def join(account)
      Current.without_account do
        @identity.users.create!(account: account, name: @name)
        @identity.reload
      end
    end
end
