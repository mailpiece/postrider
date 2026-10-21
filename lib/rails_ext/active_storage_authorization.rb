# HackerOne #3943339: never serve a blob inline with a media type a browser or
# Turbo will execute as markup. Turbo's frame renderer treats a whole family of
# declared types as HTML (FetchResponse#isHTML is
# /^(?:text\/([^\s;,]+\b)?html|application\/xhtml\+xml)\b/, so "text/x-html" or
# "text/html;charset=utf-8" count), and Content-Disposition does not stop Turbo's
# fetch. This mirrors that matcher case-insensitively and adds the scriptable
# SVG/XML types, so every such blob is forced to application/octet-stream.
ActiveStorage::DANGEROUS_INLINE_MEDIA_TYPE = %r{
  \A(?:
      text/(?:[^\s;,]+\b)?html
    | application/xhtml\+xml
    | image/svg\+xml
    | application/xml
    | text/xml
  )\b
}xi

ActiveSupport.on_load :active_storage_blob do
  def accessible_to?(user)
    attachments.includes(:record).any? { |attachment| attachment.accessible_to?(user) }
  end

  private
    def forcibly_serve_as_binary?
      super || dangerous_inline_media_type?
    end

    # A legitimate media type is ASCII. Forcing every non-ASCII one to binary also
    # keeps Ruby's Unicode \b congruent with Turbo's ASCII \b ("text/htmlé").
    def dangerous_inline_media_type?
      declared = content_type.to_s.strip
      !declared.ascii_only? || ActiveStorage::DANGEROUS_INLINE_MEDIA_TYPE.match?(declared)
    end
end

ActiveSupport.on_load :active_storage_attachment do
  def accessible_to?(user)
    record.try(:accessible_to?, user)
  end
end

Rails.application.config.to_prepare do
  # All blobs are mail attachments — require a session; never serve public.
  module ActiveStorage::Authorize
    extend ActiveSupport::Concern

    include Authentication

    included do
      # set_blob must run before require_authentication.
      skip_before_action :require_authentication
      before_action :require_authentication, :ensure_accessible
    end

    private
      def bearer_token_authenticatable_request?
        true
      end

      def ensure_accessible
        unless @blob.accessible_to?(Current.user)
          head :forbidden
        end
      end

      def http_cache_forever(**options, &block)
        super(**options, public: false, &block)
      end
  end

  ActiveStorage::Blobs::RedirectController.include ActiveStorage::Authorize
  ActiveStorage::Blobs::ProxyController.include ActiveStorage::Authorize

  # set_representation is a before_action on Representations::BaseController that runs
  # @blob.representation(...).processed, the ffmpeg/mutool/libvips parser. Registered on
  # the parent, it would precede the authorization callbacks appended above, so it is
  # re-appended to run after require_authentication and ensure_accessible.
  [ ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController ].each do |controller|
    controller.include ActiveStorage::Authorize
    controller.skip_before_action :set_representation
    controller.before_action :set_representation
  end
end
