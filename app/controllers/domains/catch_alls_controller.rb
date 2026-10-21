class Domains::CatchAllsController < ApplicationController
  wrap_parameters :domain, include: %i[ catch_all_policy ]

  include DomainScoped

  before_action :ensure_admin

  def edit
  end

  def update
    @domain.update!(domain_params)

    respond_to do |format|
      format.html { redirect_to domain_mailboxes_path(@domain), notice: "Catch-all policy updated" }
      format.json { render "domains/show" }
    end
  end

  private
    def domain_params
      params.expect(domain: %i[ catch_all_policy ])
    end
end
