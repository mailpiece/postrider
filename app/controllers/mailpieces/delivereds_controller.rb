class Mailpieces::DeliveredsController < ApplicationController
  def show
    set_page_and_extract_portion_from Current.user.accessible_mailpieces.delivered.preloaded.ordered
    fresh_when etag: [ @page.records, Current.user.accessible_mailpieces ]
  end
end
