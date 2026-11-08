class Mailboxes::ForwardingsController < ApplicationController
  include DomainScoped

  before_action :ensure_admin
  before_action :set_mailbox
  before_action :ensure_forward_confirmable
  rate_limit to: 5, within: 1.hour, only: :create

  def create
    @mailbox.send_forward_confirmation_later

    respond_to do |format|
      format.html { redirect_to [ @domain, @mailbox ], notice: "Confirmation sent to #{@mailbox.forward_to}" }
      format.json { head :created }
    end
  end

  private
    def set_mailbox
      @mailbox = @domain.mailboxes.find(params[:mailbox_id])
    end

    def ensure_forward_confirmable
      unless @mailbox.forward_confirmable?
        alert = helpers.mailbox_unconfirmable_alert(@mailbox)

        respond_to do |format|
          format.html { redirect_to [ @domain, @mailbox ], alert: alert }
          format.json { render json: { error: alert }, status: :unprocessable_entity }
        end
      end
    end
end
