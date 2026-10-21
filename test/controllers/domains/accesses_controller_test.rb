require "test_helper"

class Domains::AccessesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:private)
    @member = users(:nonstaff)
  end

  test "granting access lets a user reach the domain" do
    sign_in_as :leo
    assert_not @domain.accessible_to?(@member)

    patch domain_accesses_path(@domain), params: { domain: { all_access: false }, user_ids: [ users(:leo).id, @member.id ] }

    assert_redirected_to edit_domain_path(@domain)
    assert @domain.accessible_to?(@member)
  end

  test "revoking access takes it away" do
    sign_in_as :leo
    @domain.accesses.grant_to [ @member ]

    patch domain_accesses_path(@domain), params: { domain: { all_access: false }, user_ids: [ users(:leo).id ] }

    assert_not @domain.reload.accessible_to?(@member)
  end

  test "submitting no user ids at all leaves access alone" do
    sign_in_as :leo
    @domain.accesses.grant_to [ @member ]

    patch domain_accesses_path(@domain), params: { domain: { all_access: false } }

    assert @domain.reload.accessible_to?(@member)
    assert @domain.accessible_to?(users(:leo))
  end

  test "opening a domain grants everyone regardless of the ids submitted" do
    sign_in_as :leo

    patch domain_accesses_path(@domain), params: { domain: { all_access: true }, user_ids: [ users(:leo).id ] }

    assert @domain.reload.all_access?
    assert @domain.accessible_to?(@member)
  end

  test "removing yourself redirects to the domains rather than the domain you can no longer see" do
    sign_in_as :leo
    @domain.accesses.grant_to [ @member ]

    patch domain_accesses_path(@domain), params: { domain: { all_access: false }, user_ids: [ @member.id ] }

    assert_redirected_to domains_path
    assert_not @domain.reload.accessible_to?(users(:leo))
  end

  test "a member cannot change access" do
    sign_in_as :nonstaff
    @domain.accesses.grant_to [ @member ]

    patch domain_accesses_path(@domain), params: { domain: { all_access: true } }

    assert_response :forbidden
    assert_not @domain.reload.all_access?
  end

  test "an admin without access cannot change access on a domain they can't see" do
    sign_in_as :leo
    accesses(:private_leo).destroy

    patch domain_accesses_path(@domain), params: { domain: { all_access: true } }

    assert_response :not_found
    assert_not @domain.reload.all_access?
  end

  test "another account's domain cannot be reached" do
    sign_in_as :leo

    patch domain_accesses_path(domains(:other_account)), params: { domain: { all_access: true } }

    assert_response :not_found
  end
end
