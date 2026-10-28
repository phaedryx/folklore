# Eager-load tool classes so FolkloreMcp::Tool registration runs. In
# production with config.eager_load = true this is already done; this
# initializer covers development and test, and re-runs on code reload
# (clearing stale class references).
Rails.application.config.to_prepare do
  FolkloreMcp::Tool.registered_tools.clear
  tools_dir = Rails.root.join("app/mcp/folklore_mcp/tools")
  Rails.autoloaders.main.eager_load_dir(tools_dir) if tools_dir.exist?
end
