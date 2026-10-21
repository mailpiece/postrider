class Signups::CompletionsController < ApplicationController
  include TenantLimited

  wrap_parameters :signup, include: %i[ full_name ]

  layout "public"

  disallow_account_scope
  before_action :enforce_tenant_limit

  def new
    @signup = Signup.new(identity: Current.identity)
  end

  def create
    @signup = Signup.new(signup_params)

    if @signup.complete
      welcome_to_account
    else
      invalid_signup
    end
  end

  private
    def signup_params
      params.expect(signup: %i[ full_name ]).with_defaults(identity: Current.identity)
    end

    def welcome_to_account
      respond_to do |format|
        format.html { redirect_to landing_url(script_name: @signup.account.slug) }
        format.json { head :created }
      end
    end

    def invalid_signup
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @signup.errors.full_messages }, status: :unprocessable_entity }
      end
    end
end
