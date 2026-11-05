# Tasks

A task is an asset with a lifecycle: `pending`, then `in_progress` while an agent holds it, then `done` or `failed`
(`cancelled` is reserved). The body is the work description, and it can be read, searched, tagged and versioned like
any other asset. The lifecycle lives in a separate tasks row, so claiming a task never edits its content.

## The calls

| Tool | Arguments | Does |
|---|---|---|
| `add_task` | `path`, `name`, `content`, `content_type`, `tags`, `depends_on`, `agent` | Creates a pending task in your workspace, optionally waiting on other tasks |
| `claim_task` | `slug` or `path_prefix` (+ `tags`), `lease_seconds`, `agent` | Takes a ready task under a lease, with the outcome notes of what it depends on |
| `complete_task` | `slug`, `note`, `agent` | Marks a task you hold done, with an optional outcome note |
| `fail_task` | `slug`, `reason`, `agent` | Marks a task you hold failed, with a required reason |
| `get_pending_tasks` | `path_prefix`, `status`, `tags`, `limit`, `offset` | Lists tasks under a directory, oldest first: 100 unless you pass `limit` (at most 500) |

## Claims are leased

A claim belongs to (user, token, agent) and lasts `lease_seconds`: 1800 (30 minutes) by default, from 1 up to 604800
(a week). The claim is a single conditional update, so when two agents race for one task exactly one wins. The other
gets `Already claimed [already_claimed]: <slug> is claimed by handle/agent until ...`.

- **Renewing.** To keep a task past its lease, claim it again with the same token and agent. That sets a new lease and records a
  `task_claimed` event marked as a renewal. It does not count as a new attempt.
- **Expiry.** Once a lease runs out, anyone may claim the task. The takeover records `task_lease_expired`, naming the
  previous claimer, beside the new `task_claimed`. `attempts` counts claims by a new claimer, the first claim included;
  a renewal does not count.
- **Finishing late.** The holder can still complete or fail the task after its lease expires, as long as nobody else
  has claimed it in the meantime.

## Next-pending mode

`claim_task` without a `slug` claims the oldest task under `path_prefix` (with every tag in `tags`) that is pending or
whose lease has expired, and whose dependencies are all done (see [Dependencies](#dependencies)). Concurrent callers skip rows another caller has locked, so a pool of agents running
`claim_task(path_prefix: "you/backlog")` in a loop each get a different task. When nothing is left the answer is
`No pending task [no_pending_task]: nothing to claim under you/backlog`. When tasks remain but every one of them waits
on a dependency, the answer is `nothing ready under you/backlog; 2 blocked` instead, so a loop can tell an empty queue
from a waiting one.

## Dependencies

A task can wait on other tasks. `add_task(..., depends_on: ["<slug>", ...])` names them; each slug must be a live
task (in any workspace), or the whole call is refused naming the slug: `Not found` or `Not a task`. Dependencies are
set when the task is added and cannot be changed afterwards, so there is nothing to add or remove later and no way to
make a cycle: a new task can only depend on tasks that already exist. The slugs are kept in the `task_added` event.

**Readiness.** A task is ready when every task it depends on is `done`. A dependency that is `pending`, `in_progress`,
`failed` or `cancelled`, or whose asset has been archived, blocks it. Nothing cascades: failing a task does not fail
the tasks that depend on it. They stay `pending` and show as blocked until a person deals with it, by restoring or
re-adding the failed task, or by adding the dependent task again without the dependency.

- `claim_task` by `slug` refuses a blocked task: `Blocked [blocked]: <slug> waits on <slug>, <slug>`, naming only the
  dependencies that are not done. The holder re-claiming a task it already holds is renewing, not claiming, and is not
  refused.
- `claim_task` by `path_prefix` passes over blocked tasks and takes the oldest ready one, inside the same locked
  statement that keeps concurrent claimers apart. When only blocked tasks remain it answers
  `No pending task [no_pending_task]: nothing ready under <prefix>; N blocked`.
- A successful claim returns `dependencies`: `{slug, location, outcome_note}` for each dependency, oldest first. That
  is the handoff: the notes of the work this task builds on, without a second call.
- `get_pending_tasks` rows carry `depends_on` (every dependency) and `blocked_by` (those not done), and a blocked
  task's text line ends with `blocked by <slugs>`. `status: "ready"` lists only pending tasks with no blockers.

```
add_task(path: "you/backlog", name: "schema.md", content: "add the table")          # slug s1
add_task(path: "you/backlog", name: "endpoint.md", content: "...", depends_on: ["s1"]) # slug s2
claim_task(path_prefix: "you/backlog")      # claims s1; s2 is blocked
claim_task(path_prefix: "you/backlog")      # No pending task: nothing ready under you/backlog; 1 blocked
complete_task(slug: "s1", note: "table is tasks_v2, keyed by asset_id")
claim_task(path_prefix: "you/backlog")      # claims s2; dependencies: [{slug: "s1", outcome_note: "table is ..."}]
```

## Finish with the same agent

`complete_task` and `fail_task` work only for the (user, token, agent) that holds the claim. If several agents share one
token, pass the same `agent` you claimed with. Anyone else gets `Wrong claimer [wrong_claimer]: ...`, including another token passing
the holder's `agent`: the label alone does not make you the holder. Finishing clears the claimer and
the lease. The note or reason is kept on the task (`outcome_note`) and in the event, and the event records who
finished it. Repeating the same finish call does nothing.

## Deleting a task

Deleting (archiving) a task you or anyone else holds releases the claim: the task goes back to `pending`, and the
`asset_deleted` event names the claim it released. Restoring it brings it back unclaimed.

## Resuming after a crash

A task you were holding when your session died is not pending, so `get_pending_tasks` will not show it by default. To
resume, look for your in-progress claims first:

```
get_pending_tasks(path_prefix: "you/backlog", status: "in_progress")
```

The structured content gives each task's `claimed_by` (`handle/agent`), `lease_until` and `attempts`. Re-claim your own
to renew the lease and carry on. The listing returns 100 tasks unless you pass `limit` (1 to 500). When more
remain, `truncated` is true and the text ends with the `offset` to pass for the next page.

A claim is bound to the token that made it. If your token was revoked and you were issued a new one, you cannot renew
or finish what the old token held: wait for its lease to run out, then claim it again. `status` also accepts `ready` (pending with every dependency done), `done`, `failed`, `all` and the reserved
`cancelled`. An unknown status is
`Invalid`, not an empty list.

## Example

`ping` and `pong` share one token issued as shared (see [mcp.md](mcp.md#agent-identity)):

```
add_task(path: "you/backlog", name: "fix-login.md", content: "Login 500s when the email has a plus sign")
claim_task(path_prefix: "you/backlog", agent: "ping")       # claims fix-login.md
claim_task(path_prefix: "you/backlog", agent: "pong")       # No pending task
complete_task(slug: "<slug>", agent: "ping", note: "escaped the plus in the lookup")
```

The web UI's `/tasks` page shows the same queue, with each claimer as `handle/agent` and when its lease ends.
