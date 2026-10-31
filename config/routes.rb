Rails.application.routes.draw do
  mount FolkloreMcp::RackApp.new => "/mcp"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth
  get    "/sign_in"                 => "sessions#new",      as: :sign_in
  post   "/sign_in"                 => "sessions#create"
  delete "/sign_out"                => "sessions#destroy",  as: :sign_out
  # POST only: a GET callback could be fired by any page the browser visits (login CSRF).
  post   "/auth/:provider/callback" => "sessions#callback", as: :auth_callback
  get    "/auth/failure"            => "sessions#failure"

  namespace :api, defaults: { format: :json } do
    resources :assets, only: %i[index show create update destroy], param: :slug
  end

  namespace :settings do
    resources :tokens, only: %i[index new create destroy]
    root to: redirect("/settings/tokens")
  end

  get "/activity" => "events#index",  as: :activity
  get "/tasks"    => "tasks#index",   as: :tasks
  get "/stale"    => "stale#index",   as: :stale
  get "/search"   => "search#index",  as: :search

  # New files: /files/ sits outside every workspace (files is a reserved handle).
  get  "/files/new" => "assets#new",    as: :new_file
  post "/files"     => "assets#create", as: :files

  slug = Asset::SLUG_PATTERN
  name = %r{[^/]+}

  # Verify (and optionally reschedule) an asset from wherever it is on screen.
  post "/verifications/:slug" => "verifications#create", as: :verify_asset, constraints: { slug: }

  # A workspace's archive. `archive` is a reserved second segment, so no
  # directory can shadow it.
  get  "/:handle/archive"       => "archive#show",   as: :workspace_archive
  post "/:handle/archive/:slug" => "archive#create", as: :workspace_restore, constraints: { slug: }

  # An asset is addressed as /<dir>/<slug>/<name>, where dir is the handle
  # plus an optional location. Named `leaf` because `asset_path` is the asset
  # pipeline's. The more specific routes come first, and every one of them
  # before the browse catch-all below.
  scope "/:handle(/*location)/:slug/:name", constraints: { slug:, name: }, format: false do
    get    "versions" => "versions#index", as: :leaf_versions
    post   "versions/:version_id/restore" => "versions#restore", as: :leaf_version_restore,
           constraints: { version_id: /\d+/ }
    get    "edit" => "assets#edit", as: :edit_leaf
    get    ""     => "assets#show", as: :leaf
    patch  ""     => "assets#update"
    delete ""     => "assets#destroy"
  end

  # Workspace subtree browse: the catch-all, so it stays last. format: false
  # keeps a dotted segment from being read as a format.
  get "/:handle(/*location)" => "workspaces#show", format: false, as: :workspace

  root "home#index"
end
