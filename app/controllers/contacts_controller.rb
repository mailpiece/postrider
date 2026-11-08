class ContactsController < ApplicationController
  def index
    set_page_and_extract_portion_from Current.user.accessible_contacts.approved.alphabetically
    fresh_when etag: @page.records
  end

  def show
    @contact = Current.user.accessible_contacts.find_by!(number: params[:id])
    set_page_and_extract_portion_from @contact.mailpieces.preloaded.ordered
    fresh_when etag: [ @contact, @page.records ]
  end
end
