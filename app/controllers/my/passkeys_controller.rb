class My::PasskeysController < ApplicationController
  include ActionPack::Passkey::Request

  skip_before_action :require_account

  before_action :ensure_sudo, only: %i[ index create destroy ], unless: :no_passkeys_yet?
  before_action :set_passkey, only: %i[ edit update destroy ]

  def index
    @passkeys = my_passkeys.order(name: :asc, created_at: :desc)
    @registration_options = passkey_registration_options(holder: Current.identity)
  end

  def create
    passkey = my_passkeys.register(passkey_registration_params)

    redirect_to edit_my_passkey_path(passkey, created: true)
  rescue ActiveRecord::RecordNotUnique
    redirect_to my_passkeys_path, alert: "That passkey is already registered."
  rescue ActionPack::WebAuthn::Error
    redirect_to my_passkeys_path, alert: "We couldn't register that passkey. Please try again."
  end

  def edit
  end

  def update
    @passkey.update!(params.expect(passkey: [ :name ]))
    redirect_to my_passkeys_path
  end

  def destroy
    if my_passkeys.many?
      @passkey.destroy!
      redirect_to my_passkeys_path
    else
      redirect_to edit_my_passkey_path(@passkey), alert: "Add another passkey before you remove your only one."
    end
  end

  private
    def no_passkeys_yet?
      my_passkeys.none?
    end

    def set_passkey
      @passkey = my_passkeys.find(params[:id])
    end

    def my_passkeys
      Current.identity.passkeys
    end

    # A passkey is a web sign-in, so an API token must not be able to add or remove one.
    def bearer_token_authenticatable_request?
      false
    end
end
