require "test_helper"

class Identity::JoinableTest < ActiveSupport::TestCase
  test "join creates a new user and returns true" do
    identity = identities(:other)

    assert_difference -> { User.count }, 1 do
      assert identity.join(accounts(:davids_account)), "join should return true when creating a new user"
    end

    user = identity.users.find_by!(account: accounts(:davids_account))
    assert_equal identity.email_address, user.name
  end

  test "join with custom attributes" do
    identity = identities(:other)

    assert identity.join(accounts(:davids_account), name: "Named Joiner")

    user = identity.users.find_by!(account: accounts(:davids_account))
    assert_equal "Named Joiner", user.name
  end

  test "join returns false if user already exists" do
    identity = identities(:leo)
    account = accounts(:davids_account)

    assert identity.users.exists?(account: account), "Leo should already be a member"

    assert_no_difference -> { User.count } do
      assert_not identity.join(account), "join should return false when user already exists"
    end
  end
end
