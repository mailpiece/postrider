ActiveSupport.on_load(:active_storage_blob) do
  ActiveStorage::DiskController.after_action only: :show do
    expires_in 5.minutes, public: false
  end
end

ActiveSupport.on_load(:action_text_content) do
  # After ActionText::Engine's own Active Storage hooks.
  ActiveSupport.on_load(:active_storage_blob) do
    # Relative urls so attachments survive host name changes.
    def to_rich_text_attributes(*)
      super.merge url: Rails.application.routes.url_helpers.polymorphic_url(self, only_path: true)
    end
  end
end

# ActiveStorage::Record subclasses ActiveRecord::Base, not ApplicationRecord —
# share ApplicationRecord's pool so AS participates in the same transactions/joins.
ActiveSupport.on_load(:active_storage_record) do
  class << self
    delegate :connection_pool, to: "ApplicationRecord"
  end
end

module ActiveStorageControllerExtensions
  extend ActiveSupport::Concern

  included do
    before_action do
      # script_name keeps Disk Service upload URLs correct behind path prefixes.
      ActiveStorage::Current.url_options = {
        protocol: request.protocol,
        host: request.host,
        port: request.port,
        script_name: request.script_name
      }
    end
  end
end

module ActiveStorageDirectUploadsControllerExtensions
  extend ActiveSupport::Concern

  included do
    include Authentication
    include Authorization
    include RequestForgeryProtection
  end
end

Rails.application.config.to_prepare do
  ActiveStorage::BaseController.include ActiveStorageControllerExtensions
  ActiveStorage::DirectUploadsController.include ActiveStorageDirectUploadsControllerExtensions
end
