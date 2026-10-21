class JoinCodesController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { head :too_many_requests }

  before_action :set_join_code
  before_action :ensure_join_code_is_valid
  before_action :set_identity, only: :create

  layout "public"

  def new
  end

  def create
    if @identity == Current.identity
      @join_code.redeem_if { |account| @identity.join(account) }
      user = User.active.find_by!(account: @join_code.account, identity: @identity)

      if user.setup?
        redirect_to landing_url(script_name: @join_code.account.slug)
      else
        redirect_to new_users_verification_url(script_name: @join_code.account.slug)
      end
    else
      terminate_session if Current.identity

      if @identity.unclaimed?
        redirect_to_passkey_registration @identity, join_code: @join_code, return_to: new_users_verification_url(script_name: @join_code.account.slug)
      else
        redirect_to new_session_url(script_name: nil)
      end
    end
  end

  private
    def set_identity
      @identity = Identity.find_or_initialize_by(email_address: params.expect(:email_address))

      if @identity.new_record?
        if @identity.invalid?
          head :unprocessable_entity
        else
          @identity.save!
        end
      end
    end

    def set_join_code
      @join_code ||= Account::JoinCode.find_by(code: params.expect(:code), account: Current.account)
    end

    def ensure_join_code_is_valid
      if @join_code.nil?
        head :not_found
      elsif !@join_code.active?
        render :inactive, status: :gone
      end
    end
end
