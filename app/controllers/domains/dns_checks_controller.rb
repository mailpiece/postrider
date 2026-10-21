class Domains::DnsChecksController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  # Async either way: poll the domain itself for the statuses this settles.
  def create
    @domain.check_dns_later

    respond_to do |format|
      format.html { redirect_to edit_domain_path(@domain), notice: "Checking DNS. Give it a moment, then refresh" }
      format.json { head :accepted }
    end
  end
end
