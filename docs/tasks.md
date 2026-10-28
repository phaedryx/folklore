# Tasks

A task is an asset with a lifecycle: `pending`, then `in_progress` while an agent holds it, then `done` or `failed`
(`cancelled` is reserved). The body is the work description, and it can be read, searched, tagged and versioned like
any other asset. The lifecycle lives in a separate tasks row, so claiming a task never edits its content.

## The calls

| Tool | Arguments | Does |
|---|---|---|
| `add_task` | `path`, `name`, `content`, `content_type`, `tags` | Creates a pending task in your workspace |
| `claim_task` | `slug` or `path_prefix` (+ `tags`), `lease_seconds`, `agent` | Takes a task under a lease |
| `complete_task` | `slug`, `note`, `agent` | Marks a task you hold done, with an optional outcome note |
| `fail_task` | `slug`, `reason`, `agent` | Marks a task you hold failed, with a required reason |
| `get_pending_tasks` | `path_prefix`, `status`, `tags` | Lists tasks under a directory, oldest first |

## Claims are leased

A claim belongs to (user, agent) and lasts `lease_seconds`: 1800 (30 minutes) by default, from 1 up to 604800
(a week). The claim is a single conditional update, so when two agents race for one task exactly one wins. The other
gets `Already claimed: <slug> is claimed by handle/agent until ...`.

- **Renewing.** To keep a task past its lease, claim it again with the same agent. That sets a new lease and records a
  `task_claimed` event marked as a renewal. It does not count as a new attempt.
- **Expiry.** Once a lease runs out, anyone may claim the task. The takeover records `task_lease_expired`, naming the
  previous claimer, beside the new `task_claimed`. `attempts` counts claims by a new claimer, the first claim included;
  a renewal does not count.
- **Finishing late.** The holder can still complete or fail the task after its lease expires, as long as nobody else
  has claimed it in the meantime.

## Next-pending mode

`claim_task` without a `slug` claims the oldest task under `path_prefix` (with every tag in `tags`) that is pending or
whose lease has expired. Concurrent callers skip rows another caller has locked, so a pool of agents running
`claim_task(path_prefix: "you/backlog")` in a loop each get a different task. When nothing is left the answer is
`No pending task: nothing to claim under you/backlog`.

## Finish with the same agent

`complete_task` and `fail_task` work only for the (user, agent) that holds the claim. If several agents share one
token, pass the same `agent` you claimed with. Anyone else gets `Wrong claimer: ...`. Finishing clears the claimer and
the lease. The note or reason is kept on the task (`outcome_note`) and in the event, and the event records who
finished it. Repeating the same finish call does nothing.

## Resuming after a crash

A task you were holding when your session died is not pending, so `get_pending_tasks` will not show it by default. To
resume, look for your in-progress claims first:

```
get_pending_tasks(path_prefix: "you/backlog", status: "in_progress")
```

The structured content gives each task's `claimed_by` (`handle/agent`), `lease_until` and `attempts`. Re-claim your own
to renew the lease and carry on. `status` also accepts `done`, `failed`, `all` and the reserved `cancelled`. An unknown status is
`Invalid`, not an empty list.

## Example

```
add_task(path: "you/backlog", name: "fix-login.md", content: "Login 500s when the email has a plus sign")
claim_task(path_prefix: "you/backlog", agent: "ping")       # claims fix-login.md
claim_task(path_prefix: "you/backlog", agent: "pong")       # No pending task
complete_task(slug: "<slug>", agent: "ping", note: "escaped the plus in the lookup")
```

The web UI's `/tasks` page shows the same queue, with each claimer as `handle/agent` and when its lease ends.
