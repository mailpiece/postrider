class Domains::AllowedIpsController < ApplicationController
  include DomainScoped

  before_action :ensure_admin
  before_action :ensure_sudo

  def show
  end

  def update
    if @domain.update(domain_params)
      redirect_to domain_path(@domain), notice: "Allowed IPs updated"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def domain_params
      params.expect(domain: %i[ allowed_ips ])
    end
end
