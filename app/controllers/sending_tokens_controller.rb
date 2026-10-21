class SendingTokensController < ApplicationController
  include DomainScoped

  before_action :ensure_admin
  before_action :ensure_sudo, only: %i[ new create ]
  before_action :set_sending_token, only: %i[ show destroy ]

  def index
    set_page_and_extract_portion_from @domain.sending_tokens.ordered
  end

  def show
  end

  def new
    @sending_token = @domain.sending_tokens.new
  end

  def create
    @sending_token = @domain.sending_tokens.new(sending_token_params)

    if @sending_token.save
      respond_to do |format|
        format.html { redirect_to [ @domain, @sending_token ], notice: "Sending token created", flash: { sending_token: @sending_token.token } }
        format.json { render :create, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @sending_token.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @sending_token.destroy!

    respond_to do |format|
      format.html { redirect_to domain_sending_tokens_path(@domain), notice: "Sending token revoked" }
      format.json { head :no_content }
    end
  end

  private
    def set_sending_token
      @sending_token = @domain.sending_tokens.find(params[:id])
    end

    def sending_token_params
      params.expect(sending_token: %i[ name ])
    end
end
