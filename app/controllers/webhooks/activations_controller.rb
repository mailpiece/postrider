class Webhooks::ActivationsController < ApplicationController
  include DomainScoped

  before_action :ensure_admin
  before_action :set_webhook

  def create
    @webhook.activate

    respond_to do |format|
      format.html { redirect_to @webhook, notice: "Webhook activated" }
      format.json { render "webhooks/show", status: :created }
    end
  end

  def destroy
    @webhook.deactivate

    respond_to do |format|
      format.html { redirect_to @webhook, notice: "Webhook deactivated" }
      format.json { head :no_content }
    end
  end

  private
    def set_webhook
      @webhook = @domain.webhooks.find(params[:webhook_id])
    end
end
