class ContactsController < ApplicationController
  before_action :set_contact, only: :show

  def index
    set_page_and_extract_portion_from Current.user.accessible_contacts.approved.alphabetically
    fresh_when etag: @page.records
  end

  def show
    set_page_and_extract_portion_from @contact.mailpieces.preloaded.ordered
    fresh_when etag: [ @contact, @page.records ]
  end

  private
    def set_contact
      @contact = Current.user.accessible_contacts.find_by!(number: params[:id])
    end
end
