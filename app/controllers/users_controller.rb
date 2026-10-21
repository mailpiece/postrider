class UsersController < ApplicationController
  wrap_parameters :user, include: %i[ name ]

  before_action :set_user, except: %i[ index ]
  before_action :ensure_permission_to_change_user, only: %i[ update destroy ]
  before_action :return_here_after_sudo, only: :show, unless: -> { Current.user == @user }

  def index
    set_page_and_extract_portion_from Current.account.users.active.alphabetically.preload(:identity)
  end

  def show
  end

  def update
    if @user.update(user_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @user, notice: "Profile updated." }
        format.json { render :show }
      end
    else
      respond_to do |format|
        format.html { render :show, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @user.deactivate

    respond_to do |format|
      format.html { redirect_to users_path }
      format.json { head :no_content }
    end
  end

  private
    def set_user
      @user = Current.account.users.active.find(params[:id])
    end

    def ensure_permission_to_change_user
      head :forbidden unless Current.user.can_change?(@user)
    end

    def return_here_after_sudo
      session[:return_to_after_sudo] = request.url if Current.session && !Current.session.sudo?
    end

    def user_params
      params.expect(user: [ :name ])
    end
end
