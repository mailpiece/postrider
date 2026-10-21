module Authentication::Sudo
  extend ActiveSupport::Concern

  private
    def ensure_sudo
      # Bearer-token requests have no session and cannot confirm with a passkey, so they pass.
      if Current.session && !Current.session.sudo?
        session[:return_to_after_sudo] = request.get? ? request.url : url_from(request.referer)
        redirect_to main_app.new_my_sudo_path
      end
    end

    def after_sudo_url
      session.delete(:return_to_after_sudo) || landing_url
    end
end
