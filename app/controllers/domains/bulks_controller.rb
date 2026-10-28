class Domains::BulksController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  def create
    @domain.turn_bulk_on

    respond_to do |format|
      format.html { redirect_back fallback_location: edit_domain_path(@domain), notice: "#{@domain.name} now sends bulk mail" }
      format.json { render "domains/show" }
    end
  end

  def destroy
    @domain.turn_bulk_off

    respond_to do |format|
      format.html { redirect_back fallback_location: edit_domain_path(@domain), notice: "#{@domain.name} no longer sends bulk mail" }
      format.json { render "domains/show" }
    end
  end
end
