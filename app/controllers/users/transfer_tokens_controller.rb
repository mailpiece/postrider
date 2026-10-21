class Users::TransferTokensController < ApplicationController
  before_action :set_user
  before_action :ensure_permission_to_let_user_back_in
  before_action :ensure_sudo

  def create
    @user.identity.transfers.create!(issuer: Current.user)
    redirect_to user_path(@user)
  end

  private
    def set_user
      @user = Current.account.users.active.find(params[:user_id])
    end

    def ensure_permission_to_let_user_back_in
      head :forbidden unless Current.user.can_let_back_in?(@user)
    end
end
