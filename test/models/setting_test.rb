require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "an account gets its own setting row on create" do
    other_account = Account.create_with_owner(
      account: { name: "Other Account" },
      owner: { name: "Other Owner", identity: identities(:other) }
    )

    assert other_account.setting.persisted?
    assert_equal other_account, other_account.setting.account
    assert_not_equal accounts(:davids_account).setting, other_account.setting
  end
end
