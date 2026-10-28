# Configuration

Folklore reads its configuration from environment variables. In development and test, `dotenv` loads `.env.development`
or `.env.test` and then the matching `.env.*.local`, which git ignores. Put your own values in the `.local` file, or
export them in the shell. `.env.example` lists the variables you are likely to set.

## Setup

| Variable | Read by | Default | Meaning |
|---|---|---|---|
| `FOLKLORE_ADMIN_HANDLE` | `bin/setup` → `bin/rails folklore:admin` | none | The single user's handle. It becomes the first segment of every path they own (`you/notes/...`). It is permanent: 2 to 32 lowercase letters, digits and single hyphens, starting with a letter and not ending in a hyphen (no `_`), and not a reserved route name (`api`, `mcp`, `search`, `settings`, ...). |
| `FOLKLORE_ADMIN_EMAIL` | same | none | The user's email, used to sign in to the web UI. It is stored lowercased. |
| `FOLKLORE_ADMIN_PASSWORD` | same | none | The web sign-in password. If you leave it unset, no password is set and `bin/setup` says so; run it again with this set to add one (an existing password is never changed). |

When any of the three is unset and stdin is a terminal (and `CI` is unset), `folklore:admin` prompts for it. With no
handle or email and no terminal, it prints a notice and creates nothing. Running it again is safe: it finds the user by
email and only issues a token if the user has no active one.

## Web server and jobs

| Variable | Read by | Default | Meaning |
|---|---|---|---|
| `PORT` | `config/puma.rb`, `folklore:admin` | `3000` | The port Puma listens on. `folklore:admin` uses it in the `.mcp.json` snippet it prints. |
| `RAILS_MAX_THREADS` | `config/puma.rb`, `config/database.yml` | `3` (Puma), `5` (database pool) | Puma threads per process, and the Active Record connection pool size. |
| `PIDFILE` | `config/puma.rb` | none | Where Puma writes its pid, if set. |
| `JOB_CONCURRENCY` | `config/queue.yml` | `1` | Solid Queue worker processes. Jobs share the primary database. |
| `RAILS_LOG_LEVEL` | `config/environments/production.rb` | `info` | The production log level. Logs are one line per request (lograge). |

## Database

| Variable | Read by | Default | Meaning |
|---|---|---|---|
| `DATABASE_URL` | `config/database.yml` (production) | none | The production connection, e.g. `postgres://folklore:secret@db/folklore_production`. In development and test, Rails also merges it into the local settings when it is set. |
| `FOLKLORE_DB_SUFFIX` | `config/database.yml` (development, test) | none | An optional suffix for the local database names. With `FOLKLORE_DB_SUFFIX=foo`, the databases are `folklore_development_foo` and `folklore_test_foo`, so several checkouts of the repo on one machine do not share a database. Set it per checkout in `.env.development.local` and `.env.test.local`, which are gitignored and loaded by dotenv. Leave it unset otherwise. |

Postgres must be version 16 or newer and have the `pg_trgm` extension available. A migration enables it.

## Production

| Variable | Read by | Default | Meaning |
|---|---|---|---|
| `FOLKLORE_HOSTS` | `config/environments/production.rb` | none (any host) | Comma-separated host names the app answers to, e.g. `folklore.example.com`. This is Rails' DNS-rebinding protection. The MCP transport's own loopback-only host check is off, so set this whenever the server is reachable from other machines. |
| `RAILS_MASTER_KEY` or `SECRET_KEY_BASE` | Rails | none | Production needs one of them to sign session cookies. Set `SECRET_KEY_BASE` (generate one with `bin/rails secret`), or provide the master key for your own `config/credentials.yml.enc`. |

Phase 1 runs in single-user mode only. Team sign-in (OIDC) and a container image are planned.

## Search

| Variable | Read by | Default | Meaning |
|---|---|---|---|
| `FOLKLORE_EVAL_QUERIES` | `bin/rails folklore:search_eval`, `script/search_eval.rb` | none | The path to a search-eval queries file, when it is not given as the rake argument. See [search.md](search.md). |
| `FOLKLORE_SEARCH_LOG` | `SearchLogs::Record` | off in test | The search log is always on in development and production. In the test environment it is off unless this is `1`. |

## Test and CI only

| Variable | Read by | Meaning |
|---|---|---|
| `CI` | `config/environments/test.rb`, `folklore:admin` | When set, the test environment eager-loads the app, as production does, and `folklore:admin` never prompts. |
| `MCP_RAISE_ERRORS` | `FolkloreMcp::Tool` | In the test environment, `1` re-raises unexpected exceptions from a tool instead of answering `Internal error`. Use it to debug a failing tool test. |
| `UPDATE_SNAPSHOT` | `test/mcp/tools_list_snapshot_test.rb` | `1` rewrites `test/mcp/tools_list.snapshot.json` from the current tools. |
