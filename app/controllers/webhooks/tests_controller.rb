class Webhooks::TestsController < ApplicationController
  include DomainScoped

  before_action :ensure_admin
  before_action :set_webhook

  def create
    if @webhook.testable?
      @webhook.test
      redirect_to @webhook, notice: "Test sent. Its result will show in the deliveries below."
    else
      head :unprocessable_entity
    end
  end

  private
    def set_webhook
      @webhook = @domain.webhooks.find(params[:webhook_id])
    end
end
