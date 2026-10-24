class Domains::SwitchesController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  def show
  end
end
