ActiveSupport.on_load :active_storage_blob do
  def accessible_to?(user)
    attachments.includes(:record).any? { |attachment| attachment.accessible_to?(user) }
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
