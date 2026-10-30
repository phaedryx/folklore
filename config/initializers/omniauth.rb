Rails.application.config.middleware.use OmniAuth::Builder do
  # Phase 1 is single-user: password sign-in, plus the developer strategy when
  # FOLKLORE_DEVELOPER_SIGN_IN=1 (never in production), so a dev session needs
  # no password. OIDC arrives with team mode.
  provider :developer, fields: %i[email name], uid_field: :email if Rails.configuration.x.developer_sign_in
end

OmniAuth.config.on_failure = proc { |env| SessionsController.action(:failure).call(env) }
