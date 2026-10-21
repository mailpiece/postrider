module AccountSlug
  PATTERN = /(\d+)/
  PATH_INFO_MATCH = /\A(\/#{AccountSlug::PATTERN})/

  class Extractor
    def initialize(app)
      @app = app
    end

    # Mount the app under /:external_account_id without namespacing every route.
    def call(env)
      request = ActionDispatch::Request.new(env)

      if request.script_name && request.script_name =~ PATH_INFO_MATCH
        # Action Cable reconnect after upgrade can leave the slug on script_name.
        env["postrider.external_account_id"] = AccountSlug.decode($2)
      elsif request.path_info =~ PATH_INFO_MATCH
        request.engine_script_name = request.script_name = $1
        request.path_info   = $'.empty? ? "/" : $'

        env["postrider.external_account_id"] = AccountSlug.decode($2)
      end

      Rails.event.set_context request_id: request.request_id

      if env["postrider.external_account_id"]
        account = Account.find_by(external_account_id: env["postrider.external_account_id"])
        Rails.event.set_context account_id: account&.external_account_id
        Current.with_account(account) do
          @app.call env
        end
      else
        Current.without_account do
          @app.call env
        end
      end
    end
  end

  def self.decode(slug) slug.to_i end
  def self.encode(id) id.to_s end
end

Rails.application.config.middleware.insert_after Rack::TempfileReaper, AccountSlug::Extractor
