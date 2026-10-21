class Sessions::PasskeysController < ApplicationController
  include ActionPack::Passkey::Request

  disallow_account_scope
  require_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: :rate_limit_exceeded

  def create
    if passkey = ActionPack::Passkey.authenticate(passkey_authentication_params)
      start_new_session_for passkey.holder

      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "That passkey didn't work. Try again."
    end
  end

  private
    def rate_limit_exceeded
      redirect_to new_session_path, alert: "Try again later."
    end
end
