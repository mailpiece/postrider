class MailboxesController < ApplicationController
  include DomainScoped

  before_action :ensure_admin
  before_action :set_mailbox, only: %i[ show edit update destroy ]
  # Saving a destination mails it, so bound how fast an unconfirmed address can be pointed anywhere.
  rate_limit to: 10, within: 3.minutes, only: %i[ create update ]
  rate_limit to: 5, within: 1.hour, only: %i[ create update ], name: "forwarding", if: :forwarding?

  def index
    set_page_and_extract_portion_from @domain.mailboxes.ordered
  end

  def show
  end

  def new
    @mailbox = @domain.mailboxes.new
  end

  def create
    @mailbox = @domain.mailboxes.new(mailbox_params)

    if @mailbox.save
      respond_to do |format|
        format.html { redirect_to [ @domain, @mailbox ], notice: notice_for("Mailbox added") }
        format.json { render :create, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @mailbox.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @mailbox.update(mailbox_params)
      respond_to do |format|
        format.html { redirect_to [ @domain, @mailbox ], notice: notice_for("Mailbox updated") }
        format.json { render :show }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @mailbox.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if @mailbox.destroy
      respond_to do |format|
        format.html { redirect_to domain_mailboxes_path(@domain), notice: "Mailbox removed" }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { redirect_to domain_mailboxes_path(@domain), alert: @mailbox.errors.full_messages.to_sentence }
        format.json { render json: @mailbox.errors, status: :unprocessable_entity }
      end
    end
  end

  private
    def set_mailbox
      @mailbox = @domain.mailboxes.find(params[:id])
    end

    def mailbox_params
      if @mailbox&.persisted?
        params.expect(mailbox: %i[ forward_to ])
      else
        params.expect(mailbox: %i[ local_part forward_to ])
      end
    end

    def forwarding?
      params.dig(:mailbox, :forward_to).present?
    end

    def notice_for(saved)
      if @mailbox.should_send_forward_confirmation?
        "#{saved}. Confirmation sent to #{@mailbox.forward_to}"
      else
        saved
      end
    end
end
