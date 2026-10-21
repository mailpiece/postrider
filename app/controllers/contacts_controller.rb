class ContactsController < ApplicationController
  def index
    set_page_and_extract_portion_from Current.user.accessible_contacts.approved.ordered
    @email_counts = Contact.email_counts(@page.records)
    fresh_when etag: [ @page.records, @email_counts, Current.user.accessible_contacts ]
  end

  def show
    @contact = Current.user.accessible_contacts.find_by!(number: params[:id])
    @email_counts = Contact.email_counts([ @contact ])
    set_page_and_extract_portion_from @contact.mailpieces.preloaded.ordered
    fresh_when etag: [ @contact, @email_counts, @page.records ]
  end
end
