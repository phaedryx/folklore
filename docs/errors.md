# Errors

Every error a caller can act on is registered once, in `DomainErrors` (`app/lib/domain_errors.rb`), with a stable
code, the HTTP status it means and, for an error about one input, the field it belongs to. MCP, the JSON API and the
web UI each map an entry in one place. A new error class is not handled by any transport until it is registered, and
`test/lib/domain_errors_test.rb` fails until it is listed here.

## How each transport shows an error

**MCP** answers with `isError: true` and the text `<prefix>: <message>`. The prefix follows the status:

| Status | Prefix |
|---|---|
| 404 | `Not found` |
| 403 | `Forbidden` |
| 409 | `Conflict` |
| 422 | `Invalid` |

Four task-queue codes keep a prefix of their own: `not_a_task` (`Not a task`), `already_claimed` (`Already claimed`),
`no_pending_task` (`No pending task`) and `wrong_claimer` (`Wrong claimer`). A call made with `format: "json"` gets
`{"error": "<prefix>: <message>", "code": "<code>"}`. Anything unregistered is `Internal error`, with the details in
the server log. See [mcp.md](mcp.md#responses) for the errors the transport itself raises.

**JSON API** answers with the status and `{"status": "fail", "data": {"code": ..., "message": ...}}`. An error with a
field also carries `{"<field>": ["<message>"]}` in `data`. A record validation failure (`invalid`) carries every
field's messages that way. A missing parameter is `422` with code `missing_parameter`, and a bad or missing token is
`401` with code `unauthenticated`.

**Web** shows the 404 or 403 page for those statuses. Anything else redirects with the message as the alert: back to
the referring page after a form post, or to the page's own default after a GET. The new and edit asset forms and the
new token form re-render instead, keeping what was typed.

## Codes

| Code | Status | Field | Raised when |
|---|---|---|---|
| `not_found` | 404 | | No such live asset (archived assets are not found), or another record is missing |
| `version_not_found` | 404 | | Restoring a version (web) that is not on the asset |
| `tag_not_applied` | 404 | | `remove_tag` of a tag the asset does not have |
| `no_pending_task` | 404 | | `claim_task` with a `path_prefix` found nothing to claim |
| `forbidden` | 403 | | Writing to another user's workspace, or revoking another user's token |
| `version_conflict` | 409 | | `expected_version` is out of date (`<slug> is at version N`) |
| `name_taken` | 409 | `name` | A live asset already has that path and name |
| `already_archived` | 409 | | Archiving an archived asset |
| `not_archived` | 409 | | Restoring an asset that is not archived |
| `tag_already_applied` | 409 | | `add_tag` of a tag the asset already has |
| `already_claimed` | 409 | | `claim_task` of a task someone else holds |
| `wrong_claimer` | 409 | | Completing or failing a task you do not hold |
| `already_revoked` | 409 | | Revoking a revoked token |
| `invalid` | 422 | each invalid field | A record failed validation |
| `invalid_name` | 422 | `name` | A blank name, one with `/` or whitespace, `.` or `..`, or one over 255 characters |
| `invalid_path` | 422 | `path` | A malformed path, or one over 1024 characters |
| `reserved_path` | 422 | `path` | A path under `<handle>/state` or `<handle>/archive` |
| `invalid_location` | 422 | `location` | `read_path` or `bulk_read` given a location without a filename or workspace handle |
| `content_too_large` | 422 | `content` | Content over 1 MiB |
| `invalid_stale_after` | 422 | `stale_after` | A review date that is not `YYYY-MM-DD` |
| `invalid_status` | 422 | `status` | A note status or task status filter that is not allowed |
| `not_a_note` | 422 | | `set_status` on a task |
| `invalid_tag` | 422 | `tags` | A blank tag, or one over 100 characters |
| `not_a_task` | 422 | | A task tool given an asset that is not a task |
| `reason_required` | 422 | `reason` | `fail_task` without a reason |
| `note_too_long` | 422 | | `complete_task`'s note or `fail_task`'s reason is over 10,000 characters |
| `invalid_lease` | 422 | `lease_seconds` | A lease outside 1 to the maximum |
| `invalid_argument` | 422 | | A search or `claim_task` argument out of range, or a missing slug and prefix |
| `empty_content` | 422 | `content` | `update_last_session` with empty content |
| `no_agent` | 422 | | A checkpoint call from a web session |
| `no_handle` | 422 | | A checkpoint call from a user without a handle |
| `invalid_agent` | 422 | `agent` | An `agent` override that is malformed or reserved, or one without a token |
| `invalid_timestamp` | 422 | | `activity` given a `since` or `before` that is not ISO 8601 |
| `invalid_cursor` | 422 | | `activity` given a `since_id` or `before_id` that is not a whole number |

## Length limits

The database enforces these with CHECK constraints, and the mutations check them first so the caller sees which limit
was exceeded rather than a statement failure.

| Value | Limit | Code |
|---|---|---|
| Asset name | 255 characters | `invalid_name` |
| Asset path | 1024 characters | `invalid_path` |
| Tag | 100 characters | `invalid_tag` |
| Task outcome note (`note`, `reason`) | 10,000 characters | `note_too_long` |
| Asset content | 1 MiB | `content_too_large` |
