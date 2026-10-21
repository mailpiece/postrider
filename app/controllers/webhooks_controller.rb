class WebhooksController < ApplicationController
  wrap_parameters :webhook, include: %i[ name url subscribed_actions ]

  include DomainScoped

  before_action :ensure_admin
  before_action :ensure_sudo, only: %i[ new create edit update ]
  before_action :set_webhook, only: %i[ show edit update destroy ]

  def index
    set_page_and_extract_portion_from @domain.webhooks.ordered
  end

  def show
  end

  def new
    @webhook = @domain.webhooks.new
  end

  def create
    @webhook = @domain.webhooks.new(webhook_params)

    if @webhook.save
      respond_to do |format|
        format.html { redirect_to @webhook, notice: "Webhook added" }
        format.json { render :show, status: :created, location: domain_webhook_url(@domain, @webhook) }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @webhook.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @webhook.update(webhook_params.except(:url))
      respond_to do |format|
        format.html { redirect_to @webhook, notice: "Webhook updated" }
        format.json { render :show }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @webhook.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @webhook.destroy!

    respond_to do |format|
      format.html { redirect_to domain_webhooks_path(@domain), notice: "Webhook deleted" }
      format.json { head :no_content }
    end
  end

  private
    def set_webhook
      @webhook = @domain.webhooks.find(params[:id])
    end

    def webhook_params
      params.expect(webhook: [ :name, :url, subscribed_actions: [] ]).merge(domain_id: @domain.id)
    end
end
