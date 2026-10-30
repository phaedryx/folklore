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
what is due for review. Without a query, that lists every overdue asset, most overdue first; with one, the overdue
assets on that topic. Clients on protocol `2024-11-05` do not receive these instructions, which is why the
checkpoint tools repeat them in their own descriptions.

## Tokens and scopes

A token is `flk_` followed by 32 random characters. The server stores only its SHA-256 digest. The plaintext is shown
once, by `bin/setup` or at **Settings → Tokens**. A revoked token fails on its next request. The `Bearer` scheme is
case-insensitive.

Each token has scopes:

- `read` lets it call the read-only tools: `read`, `list`, `search`, `tags`, `versions`, `activity`,
  `get_pending_tasks` and `get_last_session`.
- `write` lets it call everything else.

A token without `write` gets `Forbidden: token lacks write scope` from any other tool, and a token without `read` gets
`Forbidden: token lacks read scope` from the read-only ones, before the tool runs. The JSON API answers the same way
with a 403: GET needs `read`, every other method `write`. New tokens get both scopes unless you untick one. Each
tool's `readOnlyHint` annotation is what decides which scope it needs.

The read-only tools write one thing: the search log. `search` records the query and `read` marks a recent search as
followed (see [search.md](search.md)). It is telemetry, so a failure to log never fails the call.

## Agent identity

Every write records who made it as (user, token, agent). The agent is the token's agent name.

A token issued as **shared** (a box at **Settings → Tokens**) is for several agents at once. Every write tool and
`get_last_session` take an optional `agent` argument, and on a shared token it sets the agent for that call. So two
agents that share one token, say `ping` and `pong`, keep separate checkpoints, exclude each other on task claims, and
are each recorded as the author of their own writes. Pass your `agent` on every call. A call without one acts as the
token's own agent name. Checkpoints are keyed by token as well, so whatever `agent` a shared token passes, it never
reads or overwrites another token's checkpoint (see [checkpoints.md](checkpoints.md)).

A token that is not shared acts only as its own agent: passing any other `agent` gets `Invalid: token "<name>" is not
shared ...` and changes nothing. Passing its own name is allowed.

**Upgrading.** Tokens issued before the shared flag existed are not shared. If several agents use one of them with
`agent`, issue a shared token at **Settings → Tokens** and move them to it, or they will get `Invalid` on every call.
A claim made through the old token stays bound to it until its lease runs out. A checkpoint an agent saved with
`agent` before the upgrade sits at `<handle>/state/<agent>`, and the shared token looks under
`<handle>/state/<token>/<agent>`: read the old one with `read_path` and save it again with `update_last_session`.

The override is a label within the token's user and can never act as another user. A task claim also records the token,
so another token passing the same `agent` is a different claimer (see [tasks.md](tasks.md)). Agent names are lowercase
slugs (`a-z`, `0-9`, `-`, `_`). `web` is reserved for the browser. The JSON API takes no `agent`: its writes are
always the token's agent.

`activity`, `versions` and the `created_by` / `updated_by` / `verified_by` fields show actors as `handle/agent`.
`updated_by` and `updated_at` describe the last edit (content, name, type or tags). Setting a status or a review date
is not an edit: `activity` records who did it.

## Who may do what

Every user can read every workspace. Writing to an asset is limited to its owner, the user whose handle is the first
segment of its path. Task lifecycle calls (`claim_task`, `complete_task`, `fail_task`) change only the task's state and
work on any task. `add_task` creates an asset, so it follows the owner rule.

The second path segment `state` (checkpoints) and `archive` are reserved: `create`, `upsert` and `add_task` refuse
them. Tools that address an existing asset by slug (`update`, `append`, `delete`, ...) still work on a checkpoint; see
[checkpoints.md](checkpoints.md).

## Responses

Every tool answers with structured content that matches its `outputSchema`, and with text. Tools that return an
asset's content (`read`, `get_last_session`, `versions` with an `id`) send it once: the text is the structured content
as JSON, as the MCP spec recommends for a tool with an output schema. The others send a short summary as text. `list`,
`search` and `get_pending_tasks` print one `slug  location` line per hit (search prints `slug  name  (dir)` with a
snippet line under it), so line-oriented scripts keep working.

`tools/list` leaves out what a client does not need: no `$schema` (MCP's default dialect is the one used), and
annotation hints only where they differ from the spec's defaults. A tool without `destructiveHint` is destructive, one
without `idempotentHint` is not idempotent, and a read-only tool carries only `readOnlyHint` and `openWorldHint`.

Errors come back with `isError: true` and one of these prefixes, as text only: some clients check any structured
content against the tool's `outputSchema`, error or not. A `read` of several refs reports each failed ref in place as
`{ref, error, code}`. [errors.md](errors.md) lists every code, the prefix and HTTP
status it maps to, and the length limits:

| Text | Meaning |
|---|---|
| `Not found: ...` | No such live asset (archived assets are not found), or no such version of it |
| `Forbidden: ...` | Not your workspace, or the token lacks the scope the tool needs |
| `Conflict: ...` | `update` got an out-of-date `expected_version` (`<slug> is at version N`), the name is taken, or the asset is already archived or not archived |
| `Invalid: ...` | A bad argument: path, name, tag, date, agent (or any `agent` on a token that is not shared), cursor, a value over its length limit, ... |
| `Invalid arguments: ...` | An argument the tool does not take, or one of the wrong type |
| `Missing required arguments: ...` | A required argument was left out |
| `Already claimed: ...`, `Wrong claimer: ...`, `No pending task: ...`, `Not a task: ...` | Task queue outcomes, see [tasks.md](tasks.md) |
| `Unauthenticated: ...` | No actor on the request |
| `Internal error` | Anything unexpected. The details go to the server log, never to the client. |

## Tools

`tools/list` is a contract, pinned by `test/mcp/tools_list.snapshot.json`. That file holds each tool's full
description, schemas and annotations. In brief:

**Reading**

- `read(ref)` returns the whole asset. `ref` is a slug or a location (`you/notes/plan.md`); a location always has a
  `/` and a slug never does. `include: [...]` returns the slug and just the fields you name: `content`, `name`,
  `path`, `content_type`, `kind`, `status`, `owner`, `tags`, `created_at`, `updated_at`, `backlinks`, `created_by`,
  `updated_by`, `verified_by`, `version`. `backlinks` lists the live assets that link here with `[[slug]]`, and is
  only returned when named. `kind` is `task` or `note`. `status` is a task's state (`pending`, `in_progress`, ...) for
  a task and the note status otherwise; the same holds in the JSON API. `version` is the counter that
  `update(expected_version:)` checks.
- `read([ref, ...])` reads up to 50 refs, slugs and locations mixed, and returns
  `{assets, bytes_returned, truncated}` in request order. A ref that fails is reported in place as
  `{ref, error, code}`. Content counts against `max_bytes` (default 100 000, at most 1 000 000); once it is spent the
  rest come back with `content_omitted: true` and `truncated` is true. An empty array or more than 50 is `Invalid`.
- `list(path)` lists a directory and its subtree, with `tags` and `sort`. It returns 100 assets from `offset` unless you
  pass `limit` (at most 500), and `next_offset` when there are more.
- `versions(slug)` lists an asset's prior versions, newest first: each one's id, when it was replaced, by whom, and its
  content type. `versions(slug, id)` returns that version's text. An archived asset's versions are not found until it
  is restored.
- `tags(within)` counts tags over live assets.
- `activity` is the event log, newest first, 50 events unless you pass `limit` (at most 200). Filter by `actor`
  (`handle`, `handle/agent` or an email), `tag`, `since` and `before` (ISO 8601, or a plain `2026-10-01 10:00:00`).
  `since_id` reads forward from an event id, oldest first. A non-numeric id is `Invalid`. Each line is
  `time  handle/agent  action  slug`, followed by the event's detail when it has one (a tag, a note, a renewal, the
  claimer whose lease ended).

**Writing**

- `create(path, name, content, content_type, tags)`: `path` is the directory and must start with your handle.
- `update(slug, content, name, content_type, tags, expected_version)` changes only the fields you pass. An empty
  `content` clears it. A content change keeps the old text as a version. A call that changes nothing records nothing.
  Pass `expected_version` (from `read(ref, include: ["version"])`) to refuse to overwrite an edit you have not seen.
- `upsert(path, name, ...)` updates the asset at that address, or creates it.
- `append(slug, text)` adds a line to the end.
- `move(slug, path, name)` gives an asset a new directory in your workspace, and a new name if you pass one. The slug
  stays, so links keep working. It records `asset_moved` with both locations.
- `delete(slug)` archives the asset (it can be restored); `restore(slug)` brings it back.
- `restore(slug, version)` puts a past version's text back on a live asset, so an agent can undo an overwrite. The
  text it replaces is kept as a version, as with any edit.
- `add_tag(slug, tag)` and `remove_tag(slug, tag)`. Tags are flat and lowercased. Adding a tag that is there, or
  removing one that is not, succeeds with `changed: false` and records nothing.

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
stops resolving until the asset is restored. `read(ref, include: ["backlinks"])` shows what links to an asset. The web UI renders
the links.

## JSON API

The same tokens authenticate `/api/assets`. Responses are `{"status": "success" | "fail", "data": ...}`.

| Request | Does |
|---|---|
| `GET /api/assets?path=you/notes&tags[]=x&limit=100&offset=0` | List a subtree, a page at a time |
| `GET /api/assets/:slug` | Read one |
| `POST /api/assets` with `{"asset": {"path", "name", "content", "content_type", "tags"}}` | Create |
| `PATCH /api/assets/:slug` with `{"asset": {"content", "name", "content_type", "tags", "expected_version"}}` | Update |
| `DELETE /api/assets/:slug` | Archive |

The list returns at most `limit` assets (default 100; a value outside 1 to 500 is clamped to that range) and
`next_offset`, the `offset` of the next page, or `null` on the last one.

A failure is `{"status": "fail", "data": {"code": ..., "message": ...}}`, and an error about one input also carries
`{"<field>": ["<message>"]}`. Status codes: 401 for no token or a bad or revoked one, 403 for not your workspace or a
token without the scope, 404 for not found, 409 for a version conflict, a taken name or an already archived asset, 422
for invalid input. [errors.md](errors.md) lists every code.
