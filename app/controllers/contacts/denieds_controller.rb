class Contacts::DeniedsController < ApplicationController
  def show
    set_page_and_extract_portion_from Current.user.accessible_contacts.denied.ordered
    fresh_when etag: [ @page.records, Current.user.screened_out_mail ]
  end
end
