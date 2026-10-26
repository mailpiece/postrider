Rails.application.config.after_initialize do
  TokenDigester.verify_pepper! unless ENV["SECRET_KEY_BASE_DUMMY"]
end
