class Domains::PeopleController < ApplicationController
  include DomainScoped

  before_action :ensure_admin

  def show
    @users = Current.account.users.active.alphabetically.includes(:identity)
    @accessed_user_ids = @domain.users.ids
  end
end
