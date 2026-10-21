class SessionsController < ApplicationController
  include ActionPack::Passkey::Request

  disallow_account_scope
  require_unauthenticated_access except: :destroy
  before_action :ensure_passkey_exists, only: :new

  layout "public"

  def new
    @authentication_options = passkey_authentication_options
  end

  def destroy
    terminate_session

    respond_to do |format|
      format.html { redirect_to_logout_url }
      format.json { head :no_content }
    end
  end

  private
    def ensure_passkey_exists
      redirect_to new_signup_path if Account.accepting_signups? && ActionPack::Passkey.none?
    end
end
