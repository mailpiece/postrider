class Users::EmailAddressesController < ApplicationController
  before_action :set_user
  rate_limit to: 5, within: 1.hour, only: :create

  def new
  end

  def create
    @user.identity.update!(email_address: new_email_address)

    respond_to do |format|
      format.html { redirect_to user_path(@user), notice: "Email address updated" }
      format.json { head :no_content }
    end
  rescue ActiveRecord::RecordNotUnique
    email_address_refused "That email address is already in use"
  rescue ActiveRecord::RecordInvalid
    email_address_refused "Please enter a valid email address"
  end

  private
    def set_user
      @user = Current.identity.users.find(params[:user_id])
    end

    def new_email_address
      params.expect :email_address
    end

    def email_address_refused(error)
      respond_to do |format|
        format.html { redirect_to new_user_email_address_path(@user), alert: error }
        format.json { render json: { error: error }, status: :unprocessable_entity }
      end
    end
end
