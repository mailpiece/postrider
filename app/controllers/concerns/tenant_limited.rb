module TenantLimited
  extend ActiveSupport::Concern

  private
    def enforce_tenant_limit
      redirect_to new_session_url unless Account.accepting_signups?
    end
end
