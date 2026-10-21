class My::MenusController < ApplicationController
  def show
    @users = Current.account.users.active.alphabetically
    @accounts = Current.identity.accounts.active

    fresh_when etag: [ @users, @accounts ]
  end
end
