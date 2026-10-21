module DomainScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_domain
  end

  private
    def set_domain
      @domain = Current.user.domains.find(params[:domain_id])
    end
end
