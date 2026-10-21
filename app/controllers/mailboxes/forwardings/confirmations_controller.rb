class Mailboxes::Forwardings::ConfirmationsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_mailbox
  before_action :ensure_forward_confirmation_token, only: :show
  rate_limit to: 10, within: 1.hour, only: :create

  def show
    if @mailbox.forwarding?
      render :confirmed
    else
      render :show
    end
  end

  def create
    if @mailbox.confirm_forwarding_using_token(token)
      respond_to do |format|
        format.html { redirect_to domain_mailbox_forwarding_confirmation_path(@domain, @mailbox, token), status: :see_other }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { render :invalid_token, status: :unprocessable_entity }
        format.json { render json: { error: "Token is invalid or has expired" }, status: :unprocessable_entity }
      end
    end
  end

  private
    # The confirmer owns the destination mailbox, not an admin session, so scope from the slug instead of Current.user.
    def set_mailbox
      @domain = Current.account.domains.find(params[:domain_id])
      @mailbox = @domain.mailboxes.find(params[:mailbox_id])
    end

    def ensure_forward_confirmation_token
      head :not_found unless @mailbox.forward_confirmation_token?(token)
    end

    def token
      params.expect :forwarding_token
    end
end
