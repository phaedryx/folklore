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
  desc "Run the search eval against a queries YAML (argument or FOLKLORE_EVAL_QUERIES)"
  task :search_eval, [ :queries_path ] => :environment do |_t, args|
    SearchEval::Runner.call(args[:queries_path].presence || ENV["FOLKLORE_EVAL_QUERIES"])
  end
end
