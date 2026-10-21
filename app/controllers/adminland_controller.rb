class AdminlandController < ApplicationController
  disallow_account_scope
  before_action :ensure_staff

  layout "public"
end
