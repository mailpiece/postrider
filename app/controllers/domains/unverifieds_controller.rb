class Domains::UnverifiedsController < ApplicationController
  def show
    set_page_and_extract_portion_from Current.user.domains.unverified.ordered
    fresh_when etag: @page.records
  end
end
