Rails.application.config.middleware.use OmniAuth::Builder do
  # Phase 1 is single-user: password sign-in, plus the developer strategy
  # locally so a dev session needs no password. OIDC arrives with team mode.
  if Rails.env.development? || Rails.env.test?
    provider :developer, fields: %i[email name], uid_field: :email
  end
end

OmniAuth.config.on_failure = proc { |env| SessionsController.action(:failure).call(env) }
