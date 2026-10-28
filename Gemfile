source "https://rubygems.org"

gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Server-rendered components [https://viewcomponent.org]
gem "view_component"

# Structured single-line per-request logs [https://github.com/roidrage/lograge]
gem "lograge"

# MCP server, mounted at /mcp; tools live in app/mcp/
gem "mcp", "~> 1.8"
gem "dry-schema"

# Password sign-in for single-user mode
gem "bcrypt", "~> 3.1.7"

# Authentication via OmniAuth (developer strategy in development and test)
gem "omniauth"
gem "omniauth-rails_csrf_protection"

# Database-backed Active Job adapter
gem "solid_queue"

# Foreman runs Procfile.dev for bin/dev (web + jobs + css)
gem "foreman", require: false

# Heroicons SVGs via `heroicon_tag` view helper
gem "heroicons-rails", "~> 1.2"

# Markdown to HTML (GFM), syntax highlighting and version diffs
gem "commonmarker", "~> 2.0"
gem "rouge", "~> 5.1"
gem "diff-lcs", "~> 2.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Environment variables loaded from .env files
  gem "dotenv-rails"

  # Test data factories
  gem "factory_bot_rails"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
