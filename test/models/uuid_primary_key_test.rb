require "test_helper"

class UuidPrimaryKeyTest < ActiveSupport::TestCase
  test "generates 25-char base36 id" do
    assert_match(/\A[0-9a-z]{25}\z/, User.new.id)
  end

  test "find by id" do
    assert_equal users(:leo), User.find(users(:leo).id)
  end

  test "fixture ids sort older than runtime records" do
    user = accounts(:davids_account).users.create!(name: "Newcomer")

    assert_operator users(:leo).id, :<, user.id
  end

  test "joins+merge shape" do
    assert_equal admin_ids, joined.map(&:id).to_set
  end

  test "joins+merge with preload" do
    assert_equal admin_ids, joined.preload(:users).map(&:id).to_set
  end

  test "includes+joins+eager_load shape" do
    eager = Identity.includes(:users).joins(:users).merge(User.admin).references(:users)

    assert_equal admin_ids, eager.map(&:id).to_set
  end

  test "where.missing" do
    assert_includes Account.where.missing(:cancellation), accounts(:davids_account)
  end

  test "has_many_through join" do
    assert_equal [ accounts(:davids_account) ], identities(:leo).accounts.to_a
  end

  private
    def admin_ids
      [ identities(:leo), identities(:other) ].map(&:id).to_set
    end

    def joined
      Identity.joins(:users).merge(User.admin)
    end
end
