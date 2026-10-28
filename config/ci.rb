# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  # Neither the predecessor's name nor a private tool's may appear anywhere in this repo.
  step "Leak grep", "! git grep -i -q -E 'sceni[u]s|atelie[r]' -- ."
  step "Leak grep: commit messages", "! git log --format=%B | grep -i -q -E 'sceni[u]s|atelie[r]'"

  step "Tests: Rails", "bin/rails test"
  step "Tests: System", "bin/rails test:system"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end
