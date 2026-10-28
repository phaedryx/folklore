# Folklore

Folklore is shared, persistent memory for coding agents. Agents read and write notes, decisions, tasks and session
checkpoints through [MCP](https://modelcontextprotocol.io). People browse and fix the same store in a read-mostly
web UI.

Everything is a Markdown (or plain text, or code) asset at a path such as `you/notes/deploy.md`. Each asset has an
8-character slug and keeps a version on every content change. Assets can be tagged and soft-deleted. Search ranks
full-text and fuzzy filename matches together. Staleness is tracked: an asset can carry a review date, and
re-confirming it is recorded as a verification, not an edit. Tasks are claimed under a lease, so two agents never hold
the same one. Each agent keeps its own checkpoint, so a new session picks up where the last one stopped.

It is a Rails 8.1 app on Postgres, MIT licensed.

## Install

You need Ruby 4.0.1 (see `.ruby-version`) and PostgreSQL 16 or newer with the `pg_trgm` extension available (it ships
with Postgres). The development and test databases are `folklore_development` and `folklore_test` on the local
server; see [docs/configuration.md](docs/configuration.md) to point elsewhere.

```sh
git clone https://github.com/phaedryx/folklore.git
cd folklore
FOLKLORE_ADMIN_HANDLE=you FOLKLORE_ADMIN_EMAIL=you@example.com FOLKLORE_ADMIN_PASSWORD=choose-one bin/setup
```

`bin/setup` installs gems, prepares the database and creates the single user. If a variable is missing it prompts for
it on a terminal. The first time, it prints an MCP token for an agent named `default`. Then it starts `bin/dev` (web
server, job runner and Tailwind watcher) on port 3000. Pass `--skip-server` to stop before the server starts.

Sign in at <http://localhost:3000/sign_in> with the email and password.

## Connect an agent

Put the token in your MCP client's configuration. For a project-level `.mcp.json`:

```json
{
  "mcpServers": {
    "folklore": {
      "type": "http",
      "url": "http://localhost:3000/mcp",
      "headers": { "Authorization": "Bearer flk_..." }
    }
  }
}
```

The token is shown once. Issue more under **Settings → Tokens** (`/settings/tokens`), one per agent: the token's agent
name labels that agent's writes, its checkpoint and its task claims. A token can be read-only. Several agents can also
share one token and tell themselves apart with the `agent` argument (see [docs/mcp.md](docs/mcp.md)).

Copy [AGENTS.md](AGENTS.md) into your projects, or merge it into your agent instructions. It tells an agent to read its
checkpoint first, to write one before it stops, and how to record mistakes and rejected approaches so they are found
again.

## Tools

| Area | Tools |
|---|---|
| Read | `read`, `read_path`, `bulk_read`, `list`, `versions`, `tags`, `activity` |
| Write | `create`, `update`, `upsert`, `append`, `delete`, `restore`, `add_tag`, `remove_tag` |
| Review | `verify`, `set_stale_after`, `set_status` |
| Search | `search` |
| Tasks | `add_task`, `claim_task`, `complete_task`, `fail_task`, `get_pending_tasks` |
| Checkpoints | `get_last_session`, `update_last_session` |

Every tool declares MCP annotations and an output schema. Each one returns structured content beside its text. The
contract is pinned by `test/mcp/tools_list.snapshot.json`. The same tokens work against a JSON API at `/api/assets`.

## Documentation

- [docs/mcp.md](docs/mcp.md): the endpoint, tokens and scopes, agent identity, errors, every tool, the JSON API
- [docs/tasks.md](docs/tasks.md): the task queue, leases and resuming after a crash
- [docs/checkpoints.md](docs/checkpoints.md): per-agent session checkpoints
- [docs/search.md](docs/search.md): how search ranks, and how to measure it
- [docs/web.md](docs/web.md): the web UI
- [docs/configuration.md](docs/configuration.md): every environment variable

## Layout

```
app/models/            thin models: validations, scopes, associations; no callbacks
app/queries/<domain>/  reads, e.g. Assets::Search, Tasks::List
app/mutations/<domain>/ writes; each owns its side effects (version, links, tags, event) in one transaction
app/mcp/folklore_mcp/  the MCP server: transport, authentication, the Tool base class
app/mcp/folklore_mcp/tools/<domain>/  one class per MCP tool
app/components/<domain>/  ViewComponents for the web UI
app/controllers/       web pages, plus api/ (JSON API) and settings/ (tokens)
app/lib/               markdown rendering, wikilinks, the search eval harness
db/structure.sql       the schema (generated tsvector columns, CHECK constraints; no triggers)
test/                  mirrors app/
```

The domains are `Assets`, `Tags`, `Versions`, `Links`, `Events`, `Tasks`, `Checkpoints`, `Tokens`, `Users` and
`SearchLogs`.

## Development

```sh
bin/dev      # web on :3000, jobs, CSS watcher
bin/ci       # setup, rubocop, bundler-audit, importmap audit, brakeman, leak greps (tree and commit
             # messages), unit and integration tests, system tests, seeds
bin/rails test
```

To change what `tools/list` returns, change the tool and then rewrite the snapshot on purpose:
`UPDATE_SNAPSHOT=1 bin/rails test test/mcp/tools_list_snapshot_test.rb`. Commit the snapshot diff with the change.

## License

MIT. See [LICENSE](LICENSE).
