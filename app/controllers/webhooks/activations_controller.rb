class Webhooks::ActivationsController < ApplicationController
  include WebhookScoped

  before_action :ensure_admin

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
end
