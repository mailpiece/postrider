# Lazy: only merges when an error is actually reported.
Rails.error.add_middleware ->(error, context:, **) do
  context.merge \
    identity_id: Current.identity&.id,
    account_id: Current.account&.external_account_id
end
