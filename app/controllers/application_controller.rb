class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include BlockSearchEngineIndexing
  include CurrentRequest, CurrentTimezone, SetPlatform
  include RequestForgeryProtection
  include TurboFlash, ViewTransitions
  include RoutingHeaders
  include GearedPagination::Controller

  # Bump to retire every cached fragment and every browser's cached page at once. It expires
  # all fragment caches together, so expect a cold-cache load at rollout.
  #
  # v3: rich text sanitized under loofah 2.25.2 and nokogiri 1.19.4 could keep a live url()
  # spelled with CSS escapes (GHSA-m3x9-938q-5767), javascript: and data:text/html URIs spelled
  # with character references (GHSA-p9wj-w8xq-vjx6, GHSA-jcff-cj73-4w4f), and unescaped < and >
  # in attribute values (GHSA-h6v6-rg66-fqj4).
  RENDERING_VERSION = "v3"

  fragment_cache_key RENDERING_VERSION
  etag { RENDERING_VERSION }
  stale_when_importmap_changes
  allow_browser versions: :modern
end
