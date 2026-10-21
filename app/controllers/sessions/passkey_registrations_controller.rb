class Sessions::PasskeyRegistrationsController < ApplicationController
  include ActionPack::Passkey::Request

  disallow_account_scope
  require_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: :rate_limit_exceeded
  before_action :set_pending_passkey_registration
  before_action :ensure_identity_is_unclaimed
  before_action :ensure_join_code_is_valid, if: :joining?

  layout "public"

  def new
    @registration_options = passkey_registration_options(holder: @identity)
  end

  def create
    @identity.passkeys.register(passkey_registration_params)
    @join_code&.redeem_if { |account| @identity.join(account) }

    clear_pending_passkey_registration_token
    start_new_session_for @identity
    redirect_to after_authentication_url
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_session_passkey_registration_path, alert: "That passkey is already registered."
  rescue ActionPack::WebAuthn::Error
    redirect_to new_session_passkey_registration_path, alert: "We couldn't register that passkey. Please try again."
  end

  private
    def set_pending_passkey_registration
      if pending = pending_passkey_registration
        @identity = Identity.find_by(id: pending["identity_id"])
        account = Account.find_by(id: pending["account_id"])
        @code = pending["join_code"]
        @join_code = Account::JoinCode.find_by(code: @code, account: account) if @code
      end
    end

    def ensure_identity_is_unclaimed
      redirect_to new_session_path unless @identity&.unclaimed?
    end

    def joining?
      @code.present?
    end

    def ensure_join_code_is_valid
      if @join_code.nil?
        head :not_found
      elsif !@join_code.active?
        render "join_codes/inactive", status: :gone
      end
    end

    def rate_limit_exceeded
      redirect_to new_session_passkey_registration_path, alert: "Try again later."
    end
end
