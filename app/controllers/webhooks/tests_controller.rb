class Webhooks::TestsController < ApplicationController
  include DomainScoped

  before_action :ensure_admin
  before_action :set_webhook
  before_action :ensure_webhook_is_testable

  def create
    @webhook.test

    respond_to do |format|
      format.html { redirect_to @webhook, notice: "Test sent. Its result will show in the deliveries below." }
      format.json { render "webhooks/show", status: :created }
    end
  end

  private
    def set_webhook
      @webhook = @domain.webhooks.find(params[:webhook_id])
    end

    def ensure_webhook_is_testable
      head :forbidden unless @webhook.testable?
    end
end
