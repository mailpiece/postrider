class EventsController < ApplicationController
  def index
    set_page_and_extract_portion_from Current.user.accessible_events.visible_to(Current.user).notable.preloaded.ordered
    fresh_when etag: @page.records
  end
end
