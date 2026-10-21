module Authentication::ViaPasskeyRegistration
  extend ActiveSupport::Concern

  PENDING_REGISTRATION_TIME = 15.minutes

  private
    def redirect_to_passkey_registration(identity, return_to:, join_code: nil)
      session[:return_to_after_authenticating] = return_to
      set_pending_passkey_registration_token(identity, join_code)

      redirect_to main_app.new_session_passkey_registration_url(script_name: nil)
    end

    def set_pending_passkey_registration_token(identity, join_code)
      cookies[:pending_passkey_registration_token] = {
        value: pending_passkey_registration_token_verifier.generate({ "identity_id" => identity.id, "account_id" => join_code&.account_id, "join_code" => join_code&.code }, expires_in: PENDING_REGISTRATION_TIME),
        httponly: true,
        same_site: :lax,
        expires: PENDING_REGISTRATION_TIME.from_now
      }
    end

    def pending_passkey_registration
      pending_passkey_registration_token_verifier.verified(cookies[:pending_passkey_registration_token])
    end

    def clear_pending_passkey_registration_token
      cookies.delete(:pending_passkey_registration_token)
    end

    def pending_passkey_registration_token_verifier
      Rails.application.message_verifier(:pending_passkey_registration)
    end
end
