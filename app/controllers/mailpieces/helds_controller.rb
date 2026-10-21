class Mailpieces::HeldsController < ApplicationController
  def show
    set_page_and_extract_portion_from Current.user.accessible_mailpieces.held.preloaded.ordered
    fresh_when etag: @page.records
  end
end
