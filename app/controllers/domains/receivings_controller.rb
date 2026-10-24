class Domains::ReceivingsController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  def create
    @domain.turn_receiving_on

    respond_to do |format|
      format.html { redirect_back fallback_location: edit_domain_path(@domain), notice: "Receiving turned on for #{@domain.name}" }
      format.json { render "domains/show" }
    end
  end

  def destroy
    @domain.turn_receiving_off

    respond_to do |format|
      format.html { redirect_back fallback_location: edit_domain_path(@domain), notice: "Receiving turned off for #{@domain.name}" }
      format.json { render "domains/show" }
    end
  end
end
