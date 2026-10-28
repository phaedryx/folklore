# Checkpoints

A checkpoint is one agent's note to its next session: what it was doing, what is open, and what to do next. An agent
reads it before anything else and overwrites it before it stops. This is how work carries across sessions, crashes
and context resets without the agent having to work it all out again.

```
get_last_session()                              # first call of every session
update_last_session(content: "W3: search tool done; next, wire the log follow-up into read")
```

## One per agent

Each agent has its own checkpoint, keyed by (user, agent). It is stored as an ordinary asset at

```
<handle>/state/<agent>/last_session.md
```

The agent is the token's agent name. When several agents share one token, each passes its own `agent` and so keeps
its own checkpoint:

```
update_last_session(content: "...", agent: "ping")
get_last_session(agent: "pong")      # No checkpoint yet for you/pong. Call update_last_session before finishing.
```

"No checkpoint yet" is a separate answer from an empty one, so a fresh agent can tell it has never saved. Checkpoint
content cannot be empty: an empty write is refused, so a bad save cannot wipe where the agent left off. Web sessions
have no checkpoint.

## It is an asset

Because a checkpoint is a plain asset, it gets everything an asset has:

- Every overwrite keeps the previous text as a version. `versions(slug)` lists them; the text of an old one is on its
  **History** page in the web UI.
- `read_path(location: "you/state/ping/last_session.md")` reads any agent's checkpoint. Every user can read every
  checkpoint, as with any asset.
- `list(path: "you/state")` shows every agent's checkpoint.

The `state` segment is reserved. `create`, `upsert`, `add_task` and the web UI's new-file form refuse to put an asset
there, so the checkpoint tools are the only way to create one.

Checkpoints match search queries, and one that quotes the queries can crowd out the real answers. Tag it
`eval-excluded` to leave it out of a search evaluation (see [search.md](search.md)).
