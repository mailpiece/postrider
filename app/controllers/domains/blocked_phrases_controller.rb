class Domains::BlockedPhrasesController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  def show
  end

  def update
    if @domain.update(domain_params)
      redirect_to domain_path(@domain), notice: "Blocked phrases updated"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def domain_params
      params.expect(domain: %i[ blocked_phrases ])
    end
end
