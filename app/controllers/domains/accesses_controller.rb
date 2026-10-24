class Domains::AccessesController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  # Commit all_access before revise: opening grants everyone (revoke then no-ops); closing leaves revocations to apply.
  def update
    @domain.update! domain_params
    @domain.accesses.revise granted: grantees, revoked: revokees if grantees_changed?

    if @domain.accessible_to?(Current.user)
      redirect_to domain_people_path(@domain), notice: "Access updated"
    else
      redirect_to domains_path, notice: "Access updated. You removed yourself from #{@domain.name}"
    end
  end

  private
    def domain_params
      params.expect(domain: %i[ all_access ])
    end

    # Missing user_ids means the checkbox array wasn't submitted, not "revoke everyone".
    def grantees_changed?
      params.key?(:user_ids)
    end

    def grantees
      @domain.account.users.active.where(id: grantee_ids)
    end

    def revokees
      @domain.users.where.not(id: grantee_ids)
    end

    def grantee_ids
      params.fetch :user_ids, []
    end
end
