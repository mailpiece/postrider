class MessagesController < ApplicationController
  skip_before_action :require_authentication, only: :create
  skip_before_action :ensure_can_access_account, only: :create

  before_action :authenticate_sending_token, only: :create
  rate_limit to: 10, within: 1.minute, name: "invalid_token", by: -> { request.remote_ip },
    unless: -> { @sending_token }, only: :create
  before_action :require_sending_token, only: :create
  before_action :require_allowed_ip, :require_submission_budget, :require_active_account, :require_from, :require_authorized_sender, only: :create

  OPTIONAL_SCALAR_KEYS = %i[
    from_name reply_to reply_to_name envelope_from return_path
    subject text html list_unsubscribe in_reply_to references
  ].freeze

  def create
    if (key = request.headers["Idempotency-Key"]).present?
      render_idempotent key
    else
      @message = Message.submit(**submit_params)
      render_submitted
    end
  end

  private
    def require_allowed_ip
      unless @sending_token.domain.allows_ip?(request.remote_ip)
        @sending_token.refuse(request.remote_ip)
        head :forbidden
      end
    end

    def require_submission_budget
      head :too_many_requests if SubmissionRateLimiter.exceeded?(@sending_token.account)
    end

    def require_active_account
      render json: { error: "account is not active" }, status: :forbidden unless Current.account.active?
    end

    def require_from
      render json: { error: "from is required" }, status: :bad_request if params[:from].blank?
    end

    def require_authorized_sender
      if (unauthorized = unauthorized_sender)
        render json: { error: "not authorized to send as #{unauthorized}" }, status: :forbidden
      end
    end

    def unauthorized_sender
      envelope = Message.envelope_sender_for(envelope_from: params[:envelope_from], return_path: params[:return_path])

      [ params[:from], envelope ].compact_blank.find do |address|
        !@sending_token.authorizes_sending_as?(address)
      end
    end

    def render_idempotent(key)
      if key.length > IdempotentRequest::MAX_KEY_LENGTH
        render json: { error: "Idempotency-Key must be #{IdempotentRequest::MAX_KEY_LENGTH} characters or fewer" }, status: :bad_request
      else
        outcome = IdempotentRequest.fulfill(@sending_token, key) do
          Message.submit(**submit_params)
        end

        case outcome.status
        when :fresh
          @message = outcome.message
          render_submitted
        when :replayed
          @message = outcome.message
          render :create, status: :created
        when :in_progress
          response.headers["Retry-After"] = "1"
          render json: { error: "a request with this Idempotency-Key is already in progress" }, status: :conflict
        end
      end
    end

    def render_submitted
      if @message.persisted?
        @sending_token.use
        render :create, status: :created
      else
        render json: @message.errors, status: :unprocessable_entity
      end
    end

    def authenticate_sending_token
      @sending_token = authenticate_with_http_token do |token, _options|
        Current.account.sending_tokens.authenticate(token)
      end
    end

    def require_sending_token
      render json: { error: "invalid token" }, status: :unauthorized unless @sending_token
    end

    def submit_params
      {
        domain: @sending_token.domain,
        from: params.expect(:from),
        **optional_scalars,
        to: recipient_list(:to),
        cc: recipient_list(:cc),
        bcc: recipient_list(:bcc),
        tags: tag_params,
        metadata: metadata_params,
        headers: header_params,
        attachments: attachment_params
      }
    end

    def optional_scalars
      params.permit(*OPTIONAL_SCALAR_KEYS).to_h.symbolize_keys
    end

    def recipient_list(key)
      if params[key].is_a?(Array)
        params[key].any? ? params.expect(key => []) : []
      elsif params[key].present?
        params[key]
      else
        []
      end
    end

    def tag_params
      if params[:tags].is_a?(Array)
        params[:tags].any? ? params.expect(tags: []) : []
      elsif params.key?(:tags)
        [ params[:tags] ]
      else
        []
      end
    end

    def metadata_params
      if params[:metadata].is_a?(ActionController::Parameters)
        params[:metadata].present? ? params.expect(metadata: {}).to_h : {}
      elsif params.key?(:metadata)
        params[:metadata]
      else
        {}
      end
    end

    def header_params
      if params[:headers].is_a?(ActionController::Parameters)
        params[:headers].present? ? params.expect(headers: {}).to_h : {}
      elsif params.key?(:headers)
        params[:headers]
      else
        {}
      end
    end

    def attachment_params
      if params[:attachments].is_a?(Array)
        params[:attachments].any? ? params.expect(attachments: [ [ :name, :content_type, :content, :cid ] ]).map(&:to_h) : []
      elsif params.key?(:attachments)
        params[:attachments]
      else
        []
      end
    end
end
