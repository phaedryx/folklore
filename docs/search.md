# Search

```
search(q: "deploy rollback", within: "you/notes", tags: ["runbook"], limit: 10)
```

`search` looks for matches in each live asset's content and in its filename. It ranks the two together and returns
`slug  name  (dir)` lines, each with a snippet around the match on the line below it.

## Filters

| Argument | Meaning |
|---|---|
| `q` | The query, in web-search syntax: words, `"quoted phrases"`, `-excluded` |
| `within` | A directory prefix; matches it and everything below it |
| `tags` | Only assets with every one of these tags |
| `exclude_tags` | Leave out assets with any of these tags |
| `status` | Note status (`open`, `done`) or a task's state (`pending`, `in_progress`, `done`, `failed`; `cancelled` is reserved) |
| `task_status` | `pending`, `in_progress`, `done` or `failed` (tasks only; `cancelled` is reserved) |
| `stale` | `true` for assets whose review date has passed; `false` for the rest. An asset with no review date is never stale. |
| `sort` | `name`, `created_at` or `updated_at`, in place of relevance |
| `limit`, `offset` | Paging. The default limit is 50 and the maximum 500. |
| `include_versions` | Also match text an asset used to contain. Such hits are snippeted from the old version and marked `(edited <date>)`. |

`stale: true` with a query finds overdue assets about one topic. For the whole review queue, open `/stale` in the web UI.

## How it ranks, and why

The ranking was tuned against a set of real queries with known answers, using the harness described below. Each step
is in place because it measured better than the obvious alternative.

1. **Content** is matched with Postgres full-text search: `websearch_to_tsquery('english', q)` against a stored,
   generated `tsvector` of the content. English stemming lets "deploying" match "deployment". The filename is
   deliberately not part of the tsvector, because a filename is a single lexeme and would barely count there.
2. **Every term first, any term only if that finds nothing.** Requiring every term is precise but brittle: one word the
   author never used empties the results. So the query is widened to any term, but only when the strict query returns
   no rows at all. Widening every time cost more precision than it gained in recall. A query with a negated term
   (`-word`) is never widened, since "anything without the word" would match almost the whole store.
3. **Filenames** are matched with trigram `word_similarity(q, name)`, with a threshold of 0.45. That compares the query
   with the best-matching part of the name, so `deploy` and the typo `deploymnet` both find `deployment-guide.md`. In
   the sweep, 0.5 rejected a filename that restated the whole query in another order, and values below 0.40 let weak
   name matches outrank real ones.
4. **The two are fused by rank, not by score.** Content relevance (`ts_rank_cd`) and name similarity are on different
   scales, and adding the two scores made the weighting an accident. Reciprocal rank fusion (k = 60) asks how near the
   top of its own list each asset came. On the eval set that lifted recall@10 from 84.2% to 89.5%. The strict and
   widened queries are not fused with each other, because the widened one is a superset and adds only noise.
5. **Ties go to the filename.** An asset that matches only by name and one that matches only by content can fuse to the
   same score. The name wins: if you search for `rails`, you most likely meant `rails.md`.

With these choices, recall@10 on the original eval set was 94.7% and top-1 84.2%.

There are no embeddings. They will be added only if they beat this on a logged eval set.

## Measuring it

The eval harness runs a list of queries with known answers through the current search, and through a fixed baseline
(every term required, unstemmed, plus a filename substring match). It reports where the expected asset landed.

```yaml
# script/search_eval_queries.yml (gitignored: it names your own assets)
- query: how do we roll back a deploy
  expect: [ab12cd34]
- query: postgres connection limits
  expect: [ef56gh78, jk90mn12]
```

```sh
bin/rails "folklore:search_eval[script/search_eval_queries.yml]"
# or
FOLKLORE_EVAL_QUERIES=script/search_eval_queries.yml bin/rails runner script/search_eval.rb
```

The output has one row per query, with its rank in the baseline and in the current search (`#1 of 12`, or `--` when
the answer is not in the top 10). A summary follows with recall@10, top-1 and mean reciprocal rank. Run it before and
after a ranking change, against the same database.

**`eval-excluded`.** Notes that quote the eval queries, such as a plan or a session checkpoint, match every query
perfectly and bury the real answers. Tag them `eval-excluded` and the harness skips them. Tagging leaves them in
place and searchable as usual.

## The search log

Each search with a query records the query, the filters that differ from their defaults, the result slugs and the
token that ran it. When the same token then reads one of those results with `read` or `read_path` within five minutes,
the search is marked as followed by that slug. Over time this gives you real queries with the answers people actually
opened, which is the raw material for a bigger eval set. It is a plain table (`search_logs`) and nothing in the app
reads it back.
