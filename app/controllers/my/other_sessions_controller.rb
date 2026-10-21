class My::OtherSessionsController < ApplicationController
  before_action :ensure_sudo

  def destroy
    Current.identity.sessions.excluding(Current.session).destroy_all
    redirect_to user_path(Current.user), notice: "Signed out of all other devices"
  end

  private
    # Signing out devices is a web action, so an API token must not be able to do it.
    def bearer_token_authenticatable_request?
      false
    end
end
