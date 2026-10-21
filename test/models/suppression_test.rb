require "test_helper"

class SuppressionTest < ActiveSupport::TestCase
  test "requires an address" do
    suppression = domains(:example).suppressions.build(address: "")

    assert_not suppression.valid?
    assert_includes suppression.errors[:address], "can't be blank"
  end

  test "address is unique within a domain" do
    duplicate = domains(:example).suppressions.build(address: suppressions(:bounced).address)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:address], "has already been taken"
  end

  # Hard bounce is per sending domain, not per account.
  test "the same address is fine on two domains of one account" do
    assert domains(:private).suppressions.build(address: suppressions(:bounced).address).valid?
  end

  test "the same address is fine on two different accounts" do
    assert domains(:other_account).suppressions.build(address: suppressions(:bounced).address).valid?
  end

  test "normalizes address by stripping whitespace and downcasing" do
    suppression = domains(:example).suppressions.create!(address: "  Bounced@Example.com  ")

    assert_equal "bounced@example.com", suppression.address
  end

  test "an account reaches its suppressions through its domains" do
    theirs = domains(:other_account).suppressions.create!(address: "elsewhere@example.com")

    assert_includes Current.account.suppressions, suppressions(:bounced)
    assert_not_includes Current.account.suppressions, theirs
  end

  test "creating and destroying a suppression maintains the domain's counter cache" do
    assert_difference -> { domains(:example).reload.suppressions_count }, 1 do
      domains(:example).suppressions.create!(address: "bounced@example.com")
    end

    assert_difference -> { domains(:example).reload.suppressions_count }, -1 do
      suppressions(:bounced).destroy!
    end
  end
end
