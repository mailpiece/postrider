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
        respond_to do |format|
          format.html { redirect_to [ @domain, @mailbox ], alert: unconfirmable_reason }
          format.json { render json: { error: unconfirmable_reason }, status: :unprocessable_entity }
        end
      end
    end

    def unconfirmable_reason
      if @domain.verified? && !@domain.sending?
        "A confirmation can't be sent: turn sending on for this domain"
      else
        "A confirmation can't be sent: check the forwarding address, and verify this domain's DKIM"
      end
    end
end
