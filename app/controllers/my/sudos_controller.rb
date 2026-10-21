class My::SudosController < ApplicationController
  include ActionPack::Passkey::Request

  skip_before_action :require_account
  rate_limit to: 10, within: 3.minutes, only: :create, with: :rate_limit_exceeded
  before_action :ensure_identity_has_a_passkey, only: :new

  def new
    @authentication_options = passkey_authentication_options(holder: Current.identity, user_verification: :required)
  end

  def create
    if Current.identity.passkeys.authenticate(passkey_authentication_params) && user_verified?
      Current.session.sudo
      redirect_to after_sudo_url
    else
      redirect_to new_my_sudo_path, alert: "That passkey didn't work. Try again."
    end
  end

  private
    def ensure_identity_has_a_passkey
      if Current.identity.passkeys.none?
        redirect_to my_passkeys_path, notice: "Add a passkey first, then try again."
      end
    end

    def user_verified?
      ActionPack::WebAuthn::Authenticator::Data.wrap(passkey_authentication_params[:authenticator_data]).user_verified?
    end

    def rate_limit_exceeded
      redirect_to new_my_sudo_path, alert: "Try again later."
    end

    def bearer_token_authenticatable_request?
      false
    end
end
