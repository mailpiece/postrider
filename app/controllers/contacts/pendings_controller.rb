class Contacts::PendingsController < ApplicationController
  def show
    set_page_and_extract_portion_from Current.user.accessible_contacts.pending.ordered
    @email_counts = Contact.email_counts(@page.records)
    @latest_held_emails = Contact.latest_held_emails(@page.records)
    fresh_when etag: [ @page.records, @email_counts, @latest_held_emails.values ]
  end
end
