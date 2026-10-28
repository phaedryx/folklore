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

  root "home#index"
end
