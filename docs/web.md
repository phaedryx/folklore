# Web UI

The web UI is for people. Use it to see what your agents wrote, fix a note by hand, review stale facts and manage
tokens. It reads and writes through the same queries and mutations as MCP, so it obeys the same rules.

## Signing in

In single-user mode, sign in at `/sign_in` with the email and password from `bin/setup`. In development and test there
is also a developer sign-in, for existing users only.

**A web session acts as the agent `web`.** Your edits, verifications, archives and restores are recorded as
`handle/web`. Tasks are read-only in the browser: claiming and finishing them is done over MCP. A web session has no token, so it is not scope-checked.
It has no checkpoint of its own, and it cannot use the `agent` override.

## Pages

| Page | Address | What it does |
|---|---|---|
| Home | `/` | Shows your MCP endpoint and links to your workspace |
| Workspace | `/<handle>` and `/<handle>/<dir>` | Tasks, then decisions and failures (by tag), then folders and the other files |
| Asset | `/<handle>/<dir>/<slug>/<name>` | Rendered content, backlinks, and Download, Edit, History, Verify and Archive |
| Raw | the asset address + `?raw=true` | The stored bytes |
| Edit | the asset address + `/edit` | Content, name and tags in a plain form |
| New file | `/files/new` | Creates a file in your workspace |
| History | the asset address + `/versions` | Every version with a line diff against the one before, and restore |
| Archive | `/<handle>/archive` | Your archived files, with restore |
| Search | `/search?q=...&tags=...` | The same search as the MCP tool |
| Review | `/stale` | Your files whose review date has passed. Verify one and set its next review date. |
| Activity | `/activity` | The event log, newest first. Filter by actor (`handle` or `handle/agent`) and tag, and page by event id. |
| Tasks | `/tasks` | Your tasks in every status, with filters |
| Tokens | `/settings/tokens` | Issue and revoke MCP tokens |

**Asset addresses.** The slug in the address is what finds the asset. When the directory or name in the address is
out of date, for example after a rename, you are redirected (302) to the current address. Only the slug is permanent,
so link to it.

**Rendering.** Markdown is rendered with tables, task lists, footnotes and highlighted code blocks. `[[slug]]` and
`[[slug|label]]` become links to the target's current address. A link to a missing slug stays as literal text. Code
files are highlighted whole, and anything else is shown as escaped text. The rendered HTML is sanitised: raw HTML,
scripts and `javascript:` and `data:` links are removed.

**Raw.** `?raw=true` serves exactly what is stored, with `Content-Security-Policy: sandbox` and
`X-Content-Type-Options: nosniff`. Even an HTML or SVG asset cannot run script or reach your session from there.

**Editing.** The edit form carries the version you loaded. If someone (or some agent) saved in the meantime, your save
is refused with a 409: the form shows the current content, your unsaved text appears read-only below it, and nothing
is written. Saving without changing anything records nothing.

**Tasks.** `/tasks` lists the oldest 100 tasks in your workspace, every status by default, and says when there are
more. A claimed task shows its claimer as `handle/agent` with "lease until ..." or "lease expired". Who finished a task
is in the activity log.

**Tokens.** `/settings/tokens` lists your tokens with their agent name, scopes, issue date, last use and status.
**New token** asks for an agent name and its scopes, `read` and `write`, both ticked by default. Untick `write` for a
token that should only read. The plaintext and a ready-to-paste `.mcp.json` snippet are shown once, on the page right
after you issue it, and never again. Revoking takes effect on the token's next request.

## Errors

A page for something that does not exist, or is archived, is a 404. Trying to change another user's workspace is a
403. Every user can read every workspace. Any other error redirects back with its message as the alert, except on the
new and edit file forms and the new token form, which re-render with the error and what you typed. See
[errors.md](errors.md).
