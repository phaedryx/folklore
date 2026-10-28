Rails.application.routes.draw do
  mount FolkloreMcp::RackApp.new => "/mcp"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth
  get    "/sign_in"                 => "sessions#new",      as: :sign_in
  post   "/sign_in"                 => "sessions#create"
  delete "/sign_out"                => "sessions#destroy",  as: :sign_out
  match  "/auth/:provider/callback" => "sessions#callback", as: :auth_callback, via: %i[get post]
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

  # Workspace subtree browse: the catch-all, so it stays last. format: false
  # keeps a dotted segment from being read as a format.
  get "/:handle(/*location)" => "workspaces#show", format: false, as: :workspace

  root "home#index"
end
