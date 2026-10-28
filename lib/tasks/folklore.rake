require "io/console"

namespace :folklore do
  desc "Provision the single-user admin from FOLKLORE_ADMIN_* and print a first MCP token"
  task admin: :environment do
    handle = ENV["FOLKLORE_ADMIN_HANDLE"].presence
    email = ENV["FOLKLORE_ADMIN_EMAIL"].presence
    password = ENV["FOLKLORE_ADMIN_PASSWORD"].presence

    if $stdin.tty?
      handle ||= prompt("Admin handle (e.g. tad)")
      email ||= prompt("Admin email")
      password ||= prompt("Admin password (web sign-in)", secret: true)
    end

    if handle.blank? || email.blank?
      puts "folklore:admin: set FOLKLORE_ADMIN_HANDLE and FOLKLORE_ADMIN_EMAIL (and optionally " \
           "FOLKLORE_ADMIN_PASSWORD) or run this from a terminal to be prompted. Nothing was created."
      next
    end

    user = Users::Provision.mutate(handle:, email:, name: handle, password:)
    puts "Admin: #{user.handle} <#{user.email}>"

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

  def prompt(label, secret: false)
    print "#{label}: "
    value = secret ? $stdin.noecho(&:gets) : $stdin.gets
    puts if secret
    value.to_s.strip.presence
  end
end
