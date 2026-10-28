# Bundles

A bundle is a folklore instance written out as plain files: one file per asset, its versions beside it, and a manifest.
It is how you back up an instance, move it to another one, or bring notes in from another system. Anything that can
write Markdown and JSON can produce one.

```
bin/rails "folklore:export[/path/to/bundle]"            # write every workspace
HANDLE=tad bin/rails "folklore:export[/path/to/bundle]" # write one workspace
DRY_RUN=1 bin/rails "folklore:import[/path/to/bundle]"  # check a bundle, write nothing
bin/rails "folklore:import[/path/to/bundle]"            # import it
```

Export writes into a directory that is empty or does not exist yet. Import checks the whole bundle before it writes
anything, and then writes it in one transaction: either every asset arrives or none does. It prints a report and
exits non-zero if the bundle was refused.

## Layout

```
<bundle>/
  manifest.json
  assets/<dir>/<name>            # live assets, one file each
  archived/<slug>/<dir>/<name>   # archived (deleted) assets
  versions/<slug>.jsonl          # an asset's earlier versions, oldest first
```

A live asset at `tad/notes/x.md` is the file `assets/tad/notes/x.md`. Archived assets sit under their slug, because
several archived assets can share a location, and one can share it with a live asset.

## manifest.json

```json
{
  "format": "folklore-bundle",
  "version": 1,
  "exported_at": "2026-10-28T17:04:11.512034Z",
  "counts": { "assets": 3, "archived": 1, "versions": 5, "tasks": 1 },
  "assets": [
    { "slug": "abcd1234", "file": "assets/tad/notes/x.md", "sha256": "9f86d08..." }
  ]
}
```

- `format` and `version` must be exactly these. Import refuses any other version.
- `counts.assets` counts every asset file, live and archived. `archived` and `tasks` count the subsets that are
  archived and that are tasks. `versions` counts the lines across all `versions/*.jsonl` files.
- `assets` lists every asset file, live and archived. `sha256` is the lowercase hex SHA-256 of the content bytes (the
  part after the front matter), or `null` when the content is null.

Import refuses a bundle whose counts do not match its files, whose files are not all listed in the manifest (or the
other way round), or whose content does not match its `sha256`.

## Asset files

Each asset file is a YAML front matter block, then the content exactly as stored:

```
---
slug: abcd1234
owner: tad
dir: tad/notes
name: x.md
content_type: text/markdown
content_nil: false
tags:
- why-not
- search
status: open
stale_after: 2026-12-01
verified_at: '2026-10-01T12:00:00.123456Z'
created_at: '2026-09-01T08:30:00.000001Z'
updated_at: '2026-09-02T08:30:00.999999Z'
---
The content, byte for byte.
```

The content starts right after the first `\n---\n` that follows the opening `---\n`, and runs to the end of the file.
Nothing is added to it: a note with no trailing newline has none in its file, CRLF line endings stay CRLF, and a body
that itself contains `---` lines is unaffected, because only the first delimiter counts. Content must be UTF-8.

| Key            | Value                                                                                       |
|----------------|---------------------------------------------------------------------------------------------|
| `slug`         | The asset's permanent id. Import keeps it, so `[[slug]]` links keep working.                |
| `owner`        | The owner's handle. It must already exist as a user on the importing instance.              |
| `dir`, `name`  | The asset's location. Same rules as anywhere else in folklore (see below).                  |
| `content_type` | A MIME type, or `null`.                                                                     |
| `content_nil`  | `true` when the content is null rather than empty. The body must then be empty.             |
| `tags`         | A list of tag names.                                                                        |
| `status`       | `null`, `open` or `done`. Must be `null` for a task.                                        |
| `stale_after`  | The review date as a YAML date (`2026-12-01`, unquoted), or `null`.                         |
| `verified_at`  | When it was last verified, or `null`.                                                       |
| `created_at`, `updated_at` | Required.                                                                       |
| `deleted_at`   | Only in `archived/` files: when it was archived.                                            |
| `task`         | Only for tasks. See below.                                                                  |

Times are strings in ISO 8601, UTC, with microseconds (`2026-09-01T08:30:00.000001Z`), so they survive the trip
exactly. Any optional key may be left out, and reads the same as `null` (an absent `tags` is an empty list).

A task carries a `task` block:

```
task:
  status: pending        # pending, done, failed or cancelled
  attempts: 0
  outcome_note: null
  created_at: '2026-09-01T08:30:00.000000Z'
  updated_at: '2026-09-01T08:30:00.000000Z'
```

`in_progress` is refused. A claim is held by a live agent under a lease, and an imported lease would describe an
agent that is not there. Write such a task as `pending` and let it be claimed again.

## Versions

`versions/<slug>.jsonl` holds one JSON object per line, oldest first:

```json
{"content": "the earlier text", "content_type": "text/markdown", "created_at": "2026-09-01T08:30:00.000000Z", "actor": "tad/ping"}
```

`actor` is `"handle"`, `"handle/agent"`, or `null`. A handle that does not exist on the importing instance is imported
as `null`. An asset with no versions has no file.

## What import checks

Before writing anything, import collects every problem in the bundle and refuses the whole of it if there are any:

- the manifest's format and version, its counts, and every file's `sha256`;
- every slug is new to this instance. Importing the same bundle twice is refused; there is no merge;
- no live asset's location is already taken here;
- every `owner` exists as a user;
- every `dir` and `name` passes folklore's usual rules. The reserved `<handle>/state` directory is allowed only as
  `<handle>/state/<agent>`, where checkpoints live (see [checkpoints](checkpoints.md));
- content is within the 1 MiB cap;
- no task is `in_progress`, and no task has a top-level `status`.

Then it inserts the assets with their slugs, timestamps and review dates as given, adds their tags, versions and task
rows, resolves `[[slug]]` links once every asset is in (so a link to an asset later in the bundle resolves), and
records one `asset_imported` event per asset. The report lists links whose target is in neither the bundle nor the
instance.

Import keeps no record of who created or last edited an asset on the instance it came from. Its history before the
import is its versions.
