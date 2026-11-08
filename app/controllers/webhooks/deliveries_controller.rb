class Webhooks::DeliveriesController < ApplicationController
  include WebhookScoped

  before_action :ensure_admin

  def index
    respond_to do |format|
      format.json do
        set_page_and_extract_portion_from @webhook.deliveries.ordered.includes(:event)
      end
    end
  end
end
