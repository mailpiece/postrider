class Contacts::ApprovalsController < ApplicationController
  before_action :set_contact

  def create
    @contact.approve

    respond_to do |format|
      format.turbo_stream { render turbo_stream: [ replaced_contact, turbo_stream_flash(notice: "Now forwarding mail from #{@contact.email}") ] }
      format.html { redirect_back fallback_location: contacts_path, notice: "Now forwarding mail from #{@contact.email}" }
      format.json { head :no_content }
    end
  end

  def destroy
    @contact.deny

    respond_to do |format|
      format.turbo_stream { render turbo_stream: [ replaced_contact, turbo_stream_flash(notice: "Now holding mail from #{@contact.email}") ] }
      format.html { redirect_back fallback_location: contacts_path, notice: "Now holding mail from #{@contact.email}" }
      format.json { head :no_content }
    end
  end

  private
    def set_contact
      @contact = Current.user.accessible_contacts.find_by!(number: params[:contact_id])
    end

    def replaced_contact
      turbo_stream.replace @contact, partial: "contacts/contact",
        locals: { contact: @contact, email_counts: Contact.email_counts([ @contact ]) }
    end
end
