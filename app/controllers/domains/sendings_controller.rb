class Domains::SendingsController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  def create
    @domain.turn_sending_on

    respond_to do |format|
      format.html { redirect_back fallback_location: edit_domain_path(@domain), notice: "Sending turned on for #{@domain.name}" }
      format.json { render "domains/show" }
    end
  end

  def destroy
    @domain.turn_sending_off

    respond_to do |format|
      format.html { redirect_back fallback_location: edit_domain_path(@domain), notice: "Sending turned off for #{@domain.name}" }
      format.json { render "domains/show" }
    end
  end
end
