class EventsController < ApplicationController
  def index
    set_page_and_extract_portion_from visible_events.notable.preloaded.ordered
    fresh_when etag: @page.records
  end

  private
    # That a domain limits IPs at all is the admins' to know.
    def visible_events
      if Current.user.admin?
        Current.user.accessible_events
      else
        Current.user.accessible_events.where.not(action: "sending_token_refused")
      end
    end
end
