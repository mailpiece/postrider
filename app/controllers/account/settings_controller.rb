class Account::SettingsController < ApplicationController
  def show
    @account = Current.account
  end
end
