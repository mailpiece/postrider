class DomainsController < ApplicationController
  before_action :ensure_admin, only: %i[ new edit create destroy ]
  before_action :ensure_sudo, only: %i[ new create ]
  before_action :set_domain, only: %i[ show edit destroy ]

  def index
    set_page_and_extract_portion_from Current.user.domains.verified.ordered
    fresh_when etag: [ @page.records, Current.user.domains ]
  end

  def show
  end

  def edit
  end

  def new
    @domain = Current.account.domains.new
  end

  def create
    @domain = Current.account.domains.new(domain_params.with_defaults(all_access: true))

    if @domain.save
      respond_to do |format|
        format.html { redirect_to domain_path(@domain), notice: "Domain added" }
        format.json { render :show, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @domain.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if @domain.destroy
      respond_to do |format|
        format.html { redirect_to domains_path, notice: "Domain removed" }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { redirect_to domain_path(@domain), alert: "#{@domain.name} still has mail. It can be removed once that ages out" }
        format.json { render json: @domain.errors, status: :unprocessable_entity }
      end
    end
  end

  private
    def set_domain
      @domain = Current.user.domains.find(params[:id])
    end

    def domain_params
      params.expect(domain: %i[ name ])
    end
end
