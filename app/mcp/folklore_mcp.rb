module FolkloreMcp
  VERSION = "0.1.0".freeze

  # Sent to the client on `initialize`, so the session-checkpoint protocol
  # travels with the server instead of being restated in every project's
  # agent instructions. Clients on protocol 2024-11-05 do not receive it,
  # which is why get_last_session/update_last_session repeat the directive in
  # their own descriptions.
  SERVER_INSTRUCTIONS = <<~TEXT.freeze
    Folklore is a shared, persistent memory for coding agents: notes,
    decisions, and tasks that outlive a session.

    Your VERY FIRST ACTION in a session should be to call `get_last_session`.
    It returns your checkpoint (where you left off) in a single read. Before
    the session ends, and at any milestone worth resuming from, call
    `update_last_session` to overwrite it.

    Facts go stale. When you re-confirm that something still holds, call
    `verify` (optionally with a `stale_after` date) rather than editing it;
    verification is recorded separately from edits. Use `search` with
    `stale: true` to find assets whose review date has passed.

    You act as the agent named by your token. When several agents share one
    token (a token issued as shared), pass your own `agent` to every write
    tool and to `get_last_session`, so each keeps its own checkpoint, task
    claims and authorship. A token that is not shared refuses an `agent`
    other than its own.
  TEXT

  def self.tool_classes
    Tool.registered_tools
  end
end
