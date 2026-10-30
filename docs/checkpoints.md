# Checkpoints

A checkpoint is one agent's note to its next session: what it was doing, what is open, and what to do next. An agent
reads it before anything else and overwrites it before it stops. This is how work carries across sessions, crashes
and context resets without the agent having to work it all out again.

```
get_last_session()                              # first call of every session
update_last_session(content: "W3: search tool done; next, wire the log follow-up into read")
```

## One per agent

Each agent has its own checkpoint, keyed by (user, token, agent). It is stored as an ordinary asset. A token's own
agent keeps it at

```
<handle>/state/<token>/last_session.md
```

where `<token>` is the token's agent name. When several agents share one token, issued as shared, each passes its own
`agent` and keeps its checkpoint under the token (a token that is not shared refuses any other `agent`; see
[mcp.md](mcp.md#agent-identity)):

```
<handle>/state/<token>/<agent>/last_session.md
```

```
update_last_session(content: "...", agent: "ping")   # you/state/team/ping/last_session.md, on a shared token named team
get_last_session(agent: "pong")      # No checkpoint yet for you/pong. Call update_last_session before finishing.
```

Because a shared token's agents live under the token's own name, no `agent` it passes can reach another token's
checkpoint: a shared token named `team` passing `agent: "ci"` gets `you/state/team/ci`, never the `ci` token's
`you/state/ci`. The key is the token's name, not the token itself, so a token reissued under the same name picks up
the old one's checkpoints.

"No checkpoint yet" is a separate answer from an empty one, so a fresh agent can tell it has never saved. `update_last_session`
refuses empty content, so a bad save cannot wipe where the agent left off. Saving the same text again writes nothing
and answers `Checkpoint unchanged at ...`, so the checkpoint keeps its old `updated` time. Web sessions
have no checkpoint.

## It is an asset

Because a checkpoint is a plain asset, it gets everything an asset has:

- Every overwrite keeps the previous text as a version. `versions(slug)` lists them; the text of an old one is on its
  **History** page in the web UI. A checkpoint keeps its 20 newest versions: each save deletes any older ones. Set
  `FOLKLORE_CHECKPOINT_VERSIONS` to keep a different number (see [configuration.md](configuration.md)).
- `read_path(location: "you/state/team/ping/last_session.md")` reads any agent's checkpoint. Every user can read every
  checkpoint, as with any asset.
- `list(path: "you/state")` shows every agent's checkpoint.

The `state` segment is reserved. `create`, `upsert`, `add_task` and the web UI's new-file form refuse it, so the
checkpoint tools are the only way to create or overwrite a checkpoint by location. A checkpoint is still an asset, so
`update`, `append`, `delete` and the web UI's edit form work on it by slug; that is how a person fixes one by hand, and
those paths do not apply the empty-content check.

Checkpoints match search queries, and one that quotes the queries can crowd out the real answers. Tag it
`eval-excluded` to leave it out of a search evaluation (see [search.md](search.md)).

## Version retention

Only checkpoints are pruned on write. Every other asset keeps all its versions until you prune them yourself:

```
bin/rails "folklore:prune_versions[50]"     # keep each asset's 50 newest versions, delete the rest
```

Newest means latest `created_at`, as the History page orders them. Pruning deletes rows outright; a bundle exported
afterwards no longer has them. Nothing runs this on a schedule. Run it from cron if you want one.
