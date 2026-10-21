class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include BlockSearchEngineIndexing
  include CurrentRequest, CurrentTimezone, SetPlatform
  include RequestForgeryProtection
  include TurboFlash, ViewTransitions
  include RoutingHeaders
  include GearedPagination::Controller

  etag { "v2" }
  stale_when_importmap_changes
  allow_browser versions: :modern
end
