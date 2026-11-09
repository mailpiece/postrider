class ScreenersController < ApplicationController
  def show
    @contacts = Current.user.accessible_contacts.pending.ordered.preloaded
    @flagged, @waiting = @contacts.partition(&:flagged?)
    fresh_when etag: @contacts
  end
end
