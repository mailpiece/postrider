class ScreenersController < ApplicationController
  def show
    set_page_and_extract_portion_from Current.user.accessible_contacts.pending.ordered
    fresh_when etag: @page.records
  end
end
