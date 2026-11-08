module WebhookScoped
  extend ActiveSupport::Concern
  include DomainScoped

  included do
    before_action :set_webhook
  end

  private
    def set_webhook
      @webhook = @domain.webhooks.find(params[:webhook_id])
    end
end
