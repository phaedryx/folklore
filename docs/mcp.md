# MCP

Folklore serves MCP over streamable HTTP at `/mcp`. The server is named `folklore`. Each request is a self-contained
JSON-RPC POST, with no session to resume, and must carry a bearer token.

```sh
curl -s -X POST http://localhost:3000/mcp \
  -H "Authorization: Bearer flk_..." \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_last_session","arguments":{}}}'
```

On `initialize`, the server sends instructions that tell the agent three things: read its checkpoint first and write
one before it stops, verify a fact that still holds instead of editing it, and use `search` with `stale: true` to find
what is due for review. Clients on protocol `2024-11-05` do not receive these instructions, which is why the
checkpoint tools repeat them in their own descriptions.

## Tokens and scopes

A token is `flk_` followed by 32 random characters. The server stores only its SHA-256 digest. The plaintext is shown
once, by `bin/setup` or at **Settings → Tokens**. A revoked token fails on its next request. The `Bearer` scheme is
case-insensitive.

Each token has scopes:

- `read` lets it call the read-only tools: `read`, `read_path`, `bulk_read`, `list`, `search`, `tags`, `versions`,
  `activity`, `get_pending_tasks` and `get_last_session`.
- `write` lets it call everything else.

A token without `write` gets `Forbidden: token lacks write scope` from any other tool, and a token without `read` gets
`Forbidden: token lacks read scope` from the read-only ones, before the tool runs. The JSON API answers the same way
with a 403: GET needs `read`, every other method `write`. New tokens get both scopes unless you untick one. Each
tool's `readOnlyHint` annotation is what decides which scope it needs.

The read-only tools write one thing: the search log. `search` records the query and `read`/`read_path` mark a recent
search as followed (see [search.md](search.md)). It is telemetry, so a failure to log never fails the call.

## Agent identity

Every write records who made it as (user, token, agent). The agent defaults to the token's agent name. The checkpoint
and task tools (`get_last_session`, `update_last_session`, `claim_task`, `complete_task`, `fail_task`) accept an
optional `agent` argument that overrides it for that call. So two agents that share one token, say `ping` and `pong`,
keep separate checkpoints and exclude each other on task claims. The override is a label within the token's user and
can never act as another user. Agent names are lowercase slugs (`a-z`, `0-9`, `-`, `_`). `web` is reserved for the
browser.

`activity`, `versions` and the `created_by` / `updated_by` / `verified_by` fields show actors as `handle/agent`.

## Who may do what

Every user can read every workspace. Writing to an asset is limited to its owner, the user whose handle is the first
segment of its path. Task lifecycle calls (`claim_task`, `complete_task`, `fail_task`) change only the task's state and
work on any task. `add_task` creates an asset, so it follows the owner rule.

The second path segment `state` (checkpoints) and `archive` are reserved: `create` and the other generic writers refuse
them.

## Responses

Every tool answers with text content. A tool that has data to return also sends it as structured content that matches
the tool's `outputSchema`. Tools that take `format: "json"` put the JSON in the text as well. `list`, `search` and
`get_pending_tasks` print one `slug  location` line per hit (search prints `slug  name  (dir)` with a snippet line
under it), so line-oriented scripts keep working.

Errors come back with `isError: true` and one of these prefixes. A call made with `format: "json"` (`read`,
`read_path`, `bulk_read`) gets the same text as `{"error": "..."}`, in the text content and the structured content:

| Text | Meaning |
|---|---|
| `Not found: <slug or location>` | No such live asset (archived assets are not found) |
| `Forbidden: ...` | Not your workspace, or the token lacks the write scope |
| `Conflict: <slug> is at version N` | `update` got an `expected_version` that is out of date |
| `Invalid: ...` | A bad argument: path, name, date, agent, cursor, content over 1 MiB, ... |
| `Invalid arguments: ...` | An argument the tool does not take, or one of the wrong type |
| `Missing required arguments: ...` | A required argument was left out |
| `Already claimed: ...`, `Wrong claimer: ...`, `No pending task: ...`, `Not a task: ...` | Task queue outcomes, see [tasks.md](tasks.md) |
| `Unauthenticated: ...` | No actor on the request |
| `Internal error` | Anything unexpected. The details go to the server log, never to the client. |

## Tools

`tools/list` is a contract, pinned by `test/mcp/tools_list.snapshot.json`. That file holds each tool's full
description, schemas and annotations. In brief:

**Reading**

- `read(slug)` returns the raw content. Boolean flags (`name`, `path`, `content_type`, `status`, `owner`, `tags`,
  `created_at`, `updated_at`, `backlinks`, `created_by`, `updated_by`, `verified_by`, `version`) return just those
  fields; add `content: true` for the body as well. `backlinks` lists the live assets that link here with `[[slug]]`.
  `status` is a task's state (`pending`, `in_progress`, ...) for a task and the note status otherwise; the same holds
  for `status` in `bulk_read` and the JSON API.
  `version` is the counter that `update(expected_version:)` checks.
- `read_path(location)` or `read_path(path, name)` does the same by address, with `with: [...]` in place of the flags.
- `bulk_read(slugs, locations)` reads many in one call under a `max_bytes` budget (default 100 000). A key that fails is
  reported in place.
- `list(path)` lists a directory and its subtree, with `tags`, `sort`, `limit` and `offset`.
- `versions(slug)` lists prior contents, newest first.
- `tags(within)` counts tags over live assets.
- `activity` is the event log, newest first. Filter by `actor` (`handle` or `handle/agent`), `tag`, `since` and
  `before` (ISO 8601). `since_id` reads forward from an event id, oldest first. A non-numeric id is `Invalid`.

**Writing**

- `create(path, name, content, content_type, tags)`: `path` is the directory and must start with your handle.
- `update(slug, content, name, content_type, tags, expected_version)` changes only the fields you pass. An empty
  `content` clears it. A content change keeps the old text as a version. A call that changes nothing records nothing.
  Pass `expected_version` (from `read(version: true)`) to refuse to overwrite an edit you have not seen.
- `upsert(path, name, ...)` updates the asset at that address, or creates it.
- `append(slug, text)` adds a line to the end.
- `delete(slug)` archives the asset (it can be restored); `restore(slug)` brings it back.
- `add_tag(slug, tag)` and `remove_tag(slug, tag)`. Tags are flat and lowercased.

**Review**

- `verify(slug, stale_after)` records that the content still holds and can schedule the next review. It is not an
  edit: no version, and `version` does not change.
- `set_stale_after(slug, stale_after)` schedules a review without claiming anything. An empty value clears it.
- `set_status(slug, status)` sets `open` or `done` on a note (not a task), or clears it.

**Search**: `search(q, ...)`, see [search.md](search.md).

**Tasks**: `add_task`, `claim_task`, `complete_task`, `fail_task` and `get_pending_tasks`, see [tasks.md](tasks.md).

**Checkpoints**: `get_last_session` and `update_last_session`, see [checkpoints.md](checkpoints.md).

## Wikilinks

`[[slug]]` or `[[slug|label]]` in content links to another asset. Links are stored when the content is written. A link
to a slug that does not exist yet is kept, and starts resolving once that asset exists. A link to an archived asset
stops resolving until the asset is restored. `read(backlinks: true)` shows what links to an asset. The web UI renders
the links.

## JSON API

The same tokens authenticate `/api/assets`. Responses are `{"status": "success" | "fail", "data": ...}`.

| Request | Does |
|---|---|
| `GET /api/assets?path=you/notes&tags[]=x` | List a subtree |
| `GET /api/assets/:slug` | Read one |
| `POST /api/assets` with `{"asset": {"path", "name", "content", "content_type", "tags"}}` | Create |
| `PATCH /api/assets/:slug` with `{"asset": {"content", "name", "content_type", "tags", "expected_version"}}` | Update |
| `DELETE /api/assets/:slug` | Archive |

Status codes: 401 for no token or a bad or revoked one, 403 for not your workspace or a token without the write scope,
404 for not found, 409 for a version conflict or an already archived asset, 422 for invalid input.
