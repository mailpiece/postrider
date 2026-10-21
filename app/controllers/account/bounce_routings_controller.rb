class Account::BounceRoutingsController < ApplicationController
  before_action :ensure_admin
  before_action :set_setting

  def edit
  end

  def update
    if @setting.update(setting_params)
      redirect_to account_settings_path, notice: "Settings saved"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_setting
      @setting = Current.account.setting
    end

    def setting_params
      params.expect(setting: %i[ bounce_address ])
    end
end
