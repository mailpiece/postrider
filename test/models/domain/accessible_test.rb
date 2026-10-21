require "test_helper"

class Domain::AccessibleTest < ActiveSupport::TestCase
  setup do
    @creator = users(:leo)
    @member = users(:nonstaff)
  end

  test "the creator gets access when the domain is created" do
    domain = create_domain "creator-access.example"

    assert domain.accessible_to?(@creator)
  end

  test "access is a row, not a role: an owner has none on a domain nobody granted them" do
    domain = create_domain "unshared.example", creator: another_admin

    assert @creator.owner?
    assert_not domain.accessible_to?(@creator)
    assert_not @creator.domains.include?(domain)
  end

  test "opening a domain grants every active user" do
    domain = domains(:private)

    assert_not domain.accessible_to?(@member)

    domain.update! all_access: true

    assert domain.accessible_to?(@member)
  end

  test "opening a domain skips the system user" do
    domain = domains(:private)

    domain.update! all_access: true

    assert domain.accessible_to?(@member)
    assert_not domain.accessible_to?(users(:system))
  end

  test "closing a domain retains the access it granted" do
    domain = domains(:example)
    assert domain.accessible_to?(@member)

    domain.update! all_access: false

    assert domain.accessible_to?(@member)
  end

  test "an open domain cannot be revoked from" do
    domain = domains(:example)

    domain.accesses.revise revoked: [ @member ]

    assert domain.accessible_to?(@member)
  end

  test "a closed domain can be revoked from" do
    domain = domains(:example)
    domain.update! all_access: false

    domain.accesses.revise revoked: [ @member ]

    assert_not domain.accessible_to?(@member)
  end

  test "revise grants and revokes in one pass" do
    domain = create_domain "revising.example", creator: another_admin

    domain.accesses.revise granted: [ @creator, @member ], revoked: []
    assert domain.accessible_to?(@creator)

    domain.accesses.revise granted: [ @member ], revoked: [ @creator ]
    assert_not domain.accessible_to?(@creator)
    assert domain.accessible_to?(@member)
  end

  test "granting twice does not duplicate the access" do
    domain = domains(:private)

    assert_no_difference -> { domain.accesses.count } do
      domain.accesses.grant_to [ @creator ]
    end
  end

  test "a new user lands in every open domain" do
    newcomer = create_user "newcomer"

    assert domains(:example).accessible_to?(newcomer)
    assert_not domains(:private).accessible_to?(newcomer)
  end

  test "a new system user is granted nothing" do
    system_user = Current.account.users.create!(name: "System", role: :system)

    assert_not domains(:example).accessible_to?(system_user)
  end

  private
    def create_domain(name, creator: @creator)
      Current.account.domains.create!(name: name, creator: creator)
    end

    def another_admin
      @another_admin ||= create_user "another-admin", role: :admin
    end

    def create_user(handle, role: :member)
      Current.account.users.create!(
        name: handle, role: role, identity: Identity.create!(email_address: "#{handle}@accessible-test.example"))
    end
end
