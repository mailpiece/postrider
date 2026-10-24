Rails.application.routes.draw do
  root "mailpieces#index"

  resource :landing, only: :show
  resource :search, only: :show

  namespace :account do
    resource :settings, only: :show
    resource :name, only: %i[ edit update ]
    resource :bounce_routing, only: %i[ edit update ]
    resource :join_code
    resource :cancellation, only: %i[ new create ]
  end

  namespace :adminland do
    resource :settings, only: :show
    resource :dns_check, only: %i[ show create ]
    resource :certificate, only: :show
    resource :certificate_renewal, only: :create
    resources :pauses, only: %i[ index destroy ]
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  resources :users, except: :edit do
    scope module: :users do
      resource :role
      resource :transfer_token, only: :create

      resources :email_addresses, only: %i[ new create ]
    end
  end

  resources :events, only: :index

  get "docs", to: "docs#show", as: :docs

  filter_path_parameters :id do
    resources :qr_codes
  end

  filter_path_parameters :code do
    get "join/:code", to: "join_codes#new", as: :join
    post "join/:code", to: "join_codes#create"
  end

  namespace :users do
    resources :joins
    resources :verifications, only: %i[ new create ]
  end

  resource :transfer_token, only: :create

  resource :session, only: %i[ new destroy ] do
    scope module: :sessions do
      filter_path_parameters :id do
        resources :transfers
      end
      resource :passkey_registration, only: %i[ new create ]
      resource :menu
      resource :passkey, only: :create
    end
  end

  get "/signup", to: redirect("/signup/new")

  resource :signup, only: %i[ new create ] do
    collection do
      scope module: :signups, as: :signup do
        resource :completion, only: %i[ new create ]
      end
    end
  end


  namespace :my do
    resource :passkey_challenge, only: :create
    resource :sudo, only: %i[ new create ]
    resource :other_sessions, only: :destroy
    resource :identity, only: :show
    resources :access_tokens
    resources :passkeys, except: %i[ show new ]
    resource :timezone
    resource :menu
  end

  namespace :domains do
    resource :unverified, only: :show
  end

  resources :domains, only: %i[ index show new edit create destroy ] do
    scope module: :domains do
      resource :dns_check, only: :create
      resource :dns_records, only: :show
      resource :people, only: :show
      resource :accesses, only: :update
      resource :blocked_phrases, only: %i[ show update ]
      resource :allowed_ips, only: %i[ show update ]
      resource :catch_all, only: %i[ edit update ]
      resource :receiving, only: %i[ create destroy ]
      resource :sending, only: %i[ create destroy ]
      resource :switches, only: :show
    end

    resources :webhooks do
      scope module: :webhooks do
        resource :activation, only: %i[ create destroy ]
        resources :deliveries, only: :index, defaults: { format: :json }
      end
    end

    resources :sending_tokens, only: %i[ index show new create destroy ]
    resources :mailboxes, only: %i[ index show new create edit update destroy ] do
      filter_path_parameters :token, :forwarding_token do
        resources :forwardings, param: :token, only: :create, module: :mailboxes do
          resource :confirmation, only: %i[ show create ], module: :forwardings
        end
      end
    end
  end
  namespace :contacts do
    resource :denied, only: :show
  end

  resources :contacts, only: %i[ index show ] do
    scope module: :contacts do
      resource :approval, only: %i[ create destroy ]
    end
  end
  resources :suppressions, only: %i[ index destroy ]
  resources :messages, only: :create
  namespace :mailpieces do
    resource :held, only: :show
    resource :discarded, only: :show
    resource :deferred, only: :show
    resource :queued, only: :show
    resource :failed, only: :show
    resource :withheld, only: :show
  end

  resources :mailpieces, only: %i[ index show destroy ] do
    resource :original, only: :show, module: :mailpieces
  end

  get "up" => "rails/health#show", as: :rails_health_check

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resolve "Webhook" do |webhook, options|
    route_for :domain_webhook, webhook.domain, webhook, options
  end

  resolve "SendingToken" do |sending_token, options|
    route_for :domain_sending_token, sending_token.domain, sending_token, options
  end

  resolve "Mailbox" do |mailbox, options|
    route_for :domain_mailbox, mailbox.domain, mailbox, options
  end
end
