# Working with Folklore memory

This project keeps its agent memory in a Folklore server, reached through the `folklore` MCP server. Copy this file
into a project, or merge it into your agent instructions, and replace `<handle>` with your workspace handle.

## Every session

1. **First call: `get_last_session`.** It returns your checkpoint, which says where the last session stopped. Read it
   before you plan anything. If several agents share one token, pass your own `agent` every time.
2. **If you work from a task queue, resume before you claim.** Call
   `get_pending_tasks(path_prefix: ..., status: "in_progress")` and pick up anything you still hold. A crashed claim
   does not show as pending.
3. **Before you finish, and at any milestone worth resuming from: `update_last_session`.** Write what is done, what is
   open, the next step, and anything the next session would otherwise have to work out again. It replaces the previous
   checkpoint, and the old text is kept as a version.

## Facts go stale

- When you re-check a note and it still holds, call `verify` (optionally with a new `stale_after` date). Do not edit
  it. A verification is recorded separately from an edit and does not create a version.
- When you know a note needs another look by some date, set it with `set_stale_after`.
- `search(q: ..., stale: true)` finds notes whose review date has passed. Check what you rely on.

## Mistakes and why-nots

Two kinds of knowledge are lost by default, because nothing else in the workflow records them. Code records what was
built. Commits and pull requests record what changed. Neither records **the wrong turn that was taken and reversed**,
or **the attractive path that was considered and killed**. Without a record, the same wrong turn gets taken again. Each
of these is one asset.

### Mistakes: `<handle>/mistakes/`

A correction that should not need making twice. Write one at the moment it happens: you acted on a wrong belief
(wrote code, made a recommendation, stated a fact) and were corrected. Propose the entry before you move on to the fix.

Name the file after the lesson, not the incident: `check-what-compels-the-read.md`, not `login-bug-mistake.md`.

```markdown
# <the lesson, as a title>

**What I did:** the action taken on the wrong belief. Be specific and unflattering.

**What's actually true:** the correction, with the evidence that settled it.

**The tell:** the situation that should make you doubt yourself next time. A tell is a recognisable moment ("any time
I recommend where to record a fact"), not a resolution ("be more careful"). This line is the point of the entry.
```

Admit an entry only if all three hold:

1. It came from a plausible but wrong belief about *this* codebase, stack, team or user, not from a slip.
2. It is likely to happen again.
3. The correction cannot be found by reading the obvious file.

Leave out typos, one-off slips, and anything a test, linter or type checker already catches. Those already have a
cheaper guard.

### Why-nots: `<handle>/why-nots/`

A path that was considered and rejected. Write one at the moment of the decision.

Name the file after the rejected path: `store-raw-transcripts.md`.

```markdown
# <the rejected path>

**Path:** what was considered, stated neutrally.

**Why it's attractive:** argued honestly. If this is weak, nobody will propose the path again and the entry does not
belong here.

**What killed it:** dated, with the specific constraint or evidence. Use several bullets if more than one thing killed
it.

**Instead:** what was done in its place.
```

Admit an entry only if both hold:

1. The path is attractive enough that someone would propose it again.
2. The reason it lost is invisible in the code: an outside party, a past incident, a team preference, a fact about
   scale.

"We picked B because A was obviously worse" is not a why-not. It is a design decision, and it belongs with the work
it decided.

### Tags

Give every entry:

- `mistake` or `why-not`, so a whole category can be pulled at once.
- **Domain tags** for the area it concerns: `postgres`, `auth`, `frontend`, `ci`, `billing`, ... These are what make
  review cheap, because they let a search cover only the area you are about to touch. An untagged entry cannot be
  found in practice.
- The ticket or story id it came from, if your team uses one, as its own tag.

### Review them before the work they could change

- **Before planning an approach**, search the why-nots for its domain, so a dead path is not proposed again:
  `search(q: "<domain>", within: "<handle>/why-nots")`.
- **Before reviewing or revising a change**, search the mistakes for the domains it touches, to catch a recurring wrong
  belief before someone has to correct it again: `search(q: "<domain>", within: "<handle>/mistakes")`.

Search by domain. Do not list the whole directory. An entry nobody searches for is as good as no entry.

### Staleness

A why-not is only as good as the constraint that killed it. When that constraint might lift (a vendor limit, a
missing feature, a scale fact), set `stale_after` so the entry comes up for review instead of quietly blocking a path
that has become viable. If it still holds when it comes due, `verify` it. Do not edit it.

A mistake rarely goes stale, but it becomes obsolete when the code it describes is restructured. Delete it then, so it
does not misfire.

## Where to put things

A note is read only when something makes someone read it. Its quality, structure and location do not decide that.
Before you record something "for later", name the mechanism that will cause the read: this file, which your
instructions load every session; the checkpoint, which you read first; a search you are told to run before a kind of
work. If you cannot name one, the note will not be read, and filing it is no better than discarding it.

So:

- Resume state goes in the checkpoint.
- Lessons and rejected paths go in `mistakes/` and `why-nots/`, tagged by domain, because this file tells you to search
  them.
- Work for later goes in a task (`add_task`), because the queue is checked.
- Store residue, not records: decisions, lessons and state. Do not paste raw transcripts or logs.

## Small habits

- Link related notes with `[[slug]]`. `read(slug, backlinks: true)` shows what links to a note.
- Use `update(..., expected_version: N)` when you are editing something another agent might also be editing.
  `read(slug, version: true)` gives you N.
- Archive with `delete`; it can be undone with `restore`.
