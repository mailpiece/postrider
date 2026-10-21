class Account::NamesController < ApplicationController
  wrap_parameters :account, include: %i[ name ]

  before_action :ensure_admin
  before_action :set_account

  def edit
  end

  def update
    if @account.update(name_params)
      respond_to do |format|
        format.html { redirect_to account_settings_path, notice: "Settings saved" }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  private
    def set_account
      @account = Current.account
    end

    def name_params
      params.expect account: %i[ name ]
    end
end
