class Contacts::DeniedsController < ApplicationController
  def show
    set_page_and_extract_portion_from Current.user.accessible_contacts.denied.ordered
    @email_counts = Contact.email_counts(@page.records)
    fresh_when etag: [ @page.records, @email_counts ]
  end
end
