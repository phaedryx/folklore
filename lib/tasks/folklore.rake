require "io/console"

namespace :folklore do
  desc "Provision the single-user admin from FOLKLORE_ADMIN_* and print a first MCP token"
  task admin: :environment do
    handle = ENV["FOLKLORE_ADMIN_HANDLE"].presence
    email = ENV["FOLKLORE_ADMIN_EMAIL"].presence
    password = ENV["FOLKLORE_ADMIN_PASSWORD"].presence

    if $stdin.tty? && ENV["CI"].blank?
      handle ||= FolkloreAdminPrompt.prompt("Admin handle (e.g. tad)")
      email ||= FolkloreAdminPrompt.prompt("Admin email")
      password ||= FolkloreAdminPrompt.prompt("Admin password (web sign-in)", secret: true)
    end

    if handle.blank? || email.blank?
      puts "folklore:admin: set FOLKLORE_ADMIN_HANDLE and FOLKLORE_ADMIN_EMAIL (and optionally " \
           "FOLKLORE_ADMIN_PASSWORD) or run this from a terminal to be prompted. Nothing was created."
      next
    end

    user = Users::Provision.mutate(handle:, email:, name: handle, password:)
    puts "Admin: #{user.handle} <#{user.email}>"
    if user.password_digest.blank?
      puts "No web password is set, so the web UI cannot be signed into yet. Run this again with " \
           "FOLKLORE_ADMIN_PASSWORD set to add one."
    end

    if user.tokens.active.exists?
      puts "An MCP token already exists for #{user.handle}; issue another from the web UI or `bin/rails runner`."
    else
      result = Tokens::Issue.mutate(user:, agent_name: "default")
      port = ENV.fetch("PORT", "3000")
      puts <<~TEXT

        Your MCP token (shown once, store it now):

          #{result.plaintext}

        Add to .mcp.json (or your client's MCP config):

          {
            "mcpServers": {
              "folklore": {
                "type": "http",
                "url": "http://localhost:#{port}/mcp",
                "headers": { "Authorization": "Bearer #{result.plaintext}" }
              }
            }
          }
      TEXT
    end
  end
end

module FolkloreAdminPrompt
  def self.prompt(label, secret: false)
    print "#{label}: "
    value = secret ? $stdin.noecho(&:gets) : $stdin.gets
    puts if secret
    value.to_s.strip.presence
  end
end

namespace :folklore do
  desc "Run the search eval: the committed synthetic set, or a queries YAML (argument or FOLKLORE_EVAL_QUERIES)"
  task :search_eval, [ :queries_path ] => :environment do |_t, args|
    queries_path = args[:queries_path].presence || ENV["FOLKLORE_EVAL_QUERIES"].presence
    queries_path ? SearchEval::Runner.call(queries_path) : SearchEval::Synthetic.call
  rescue SearchEval::Runner::MissingQueriesError, SearchEval::Runner::UnknownSlugError => e
    abort "folklore:search_eval: #{e.message}"
  end
end

namespace :folklore do
  desc "Write every asset to a bundle directory (HANDLE=<handle> for one workspace); see docs/bundle.md"
  task :export, [ :path ] => :environment do |_t, args|
    abort "usage: bin/rails \"folklore:export[path/to/bundle]\"" if args[:path].blank?

    result = Bundles::Export.query(dir: args[:path], handle: ENV["HANDLE"])
    counts = result.counts
    puts "Exported #{counts[:assets]} assets (#{counts[:archived]} archived, #{counts[:tasks]} tasks) " \
         "and #{counts[:versions]} versions to #{args[:path]}"
  rescue Bundles::Export::NotEmptyError => e
    abort "folklore:export: #{e.message}. Export into an empty or new directory."
  end
end

namespace :folklore do
  desc "Import a bundle directory in one transaction (DRY_RUN=1 to check it and write nothing); see docs/bundle.md"
  task :import, [ :path ] => :environment do |_t, args|
    abort "usage: bin/rails \"folklore:import[path/to/bundle]\"" if args[:path].blank?

    report = Bundles::Import.mutate(dir: args[:path], dry_run: ENV["DRY_RUN"].present?)
    counts = report.counts
    puts "#{report.dry_run ? 'Would import' : 'Imported'} #{counts[:assets]} assets (#{counts[:archived]} archived, " \
         "#{counts[:tasks]} tasks) and #{counts[:versions]} versions from #{args[:path]}#{' (dry run)' if report.dry_run}"
    if report.dangling_links.any?
      puts "#{report.dangling_links.size} links name an asset in neither the bundle nor this instance:"
      report.dangling_links.each { |link| puts "  #{link[:location]} (#{link[:slug]}) -> [[#{link[:ref]}]]" }
    end
  rescue Bundles::Import::RejectedError => e
    warn "folklore:import: #{e.message}. Nothing was written."
    e.errors.each { |error| warn "  #{error}" }
    exit 1
  end
end

namespace :folklore do
  desc "Delete search logs older than DAYS (default 180); see docs/search.md"
  task :prune_search_logs, [ :days ] => :environment do |_t, args|
    days = args[:days].presence || SearchLogs::Prune::DEFAULT_RETENTION.in_days.to_i
    abort "folklore:prune_search_logs: days must be a positive whole number, got #{days.inspect}" unless days.to_s.match?(/\A[1-9]\d*\z/)

    deleted = SearchLogs::Prune.mutate(older_than: days.to_i.days)
    puts "Deleted #{deleted} search #{'log'.pluralize(deleted)} older than #{days} days"
  end
end
