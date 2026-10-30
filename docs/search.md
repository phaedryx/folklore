# Search

```
search(q: "deploy rollback", within: "you/notes", tags: ["runbook"], limit: 10)
```

`search` looks for matches in each live asset's content and in its filename. It ranks the two together and returns
`slug  name  (dir)` lines, each with a snippet around the match on the line below it.

## Filters

| Argument | Meaning |
|---|---|
| `q` | The query, in web-search syntax: words, `"quoted phrases"`, `-excluded`. Optional only with `stale: true` |
| `within` | A directory prefix; matches it and everything below it |
| `tags` | Only assets with every one of these tags |
| `exclude_tags` | Leave out assets with any of these tags |
| `status` | Note status (`open`, `done`) or a task's state (`pending`, `in_progress`, `done`, `failed`; `cancelled` is reserved) |
| `task_status` | `pending`, `in_progress`, `done` or `failed` (tasks only; `cancelled` is reserved) |
| `stale` | `true` for assets whose review date has passed; `false` for the rest. An asset with no review date is never stale. |
| `sort` | `name`, `created_at` or `updated_at`, in place of relevance |
| `limit`, `offset` | Paging. The default limit is 50 and the maximum 500. |
| `include_versions` | Also match text an asset used to contain. Such hits are snippeted from the old version and marked `(edited <date>)`. |

`q` is required, except with `stale: true`. There, a query finds overdue assets about one topic, and leaving it out
lists every overdue asset, most overdue first: the same review queue as `/stale` in the web UI.

## How it ranks, and why

The ranking was tuned against a set of 19 real queries with known answers from one private store, using the harness
described below. Each step is in place because it measured better than the obvious alternative on that set. The set
named real assets, so it was never published and those figures cannot be reproduced; they are kept below as the
reason for each choice. The numbers anyone can check come from the synthetic set under
[Measuring it](#measuring-it).

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
   name matches outrank real ones. The lookup uses the `<%` operator, which the trigram index on `name` can answer
   (a `word_similarity()` call cannot, and forced a read of every row). `<%` takes its cutoff from
   `pg_trgm.word_similarity_threshold`, which `config/database.yml` sets to the same 0.45.
4. **The two are fused by rank, not by score.** Content relevance (`ts_rank_cd`) and name similarity are on different
   scales, and adding the two scores made the weighting an accident. Reciprocal rank fusion (k = 60) asks how near the
   top of its own list each asset came. On the private set that lifted recall@10 from 84.2% to 89.5%. Each list holds
   only the assets its own retriever matched, under the same filters as the results: an asset whose name misses the
   threshold has no name rank at all, and a search scoped by `within`, tags, status or `stale` is ranked within that
   scope. Assets that score the same within a list share its rank. The strict and widened queries are not fused with
   each other, because the widened one is a superset and adds only noise.
5. **Ties go to the filename.** An asset that matches only by name and one that matches only by content can fuse to the
   same score. The name wins: if you search for `rails`, you most likely meant `rails.md`.

With these choices, recall@10 on the private set was 94.7% and top-1 84.2%. That run predates two fixes to the
fusion: it ranked every matched asset in both lists, so an asset with no name match still took a name rank decided by
its id, and it ranked across the whole store whatever the filters. On the synthetic set, fixing those moved top-1
from 82.1% to 89.3%.

There are no embeddings. They will be added only if they beat this on a logged eval set.

## Measuring it

The eval harness runs a list of queries with known answers through the current search, and through a fixed baseline
(every term required, unstemmed, plus a filename substring match, ordered by its own `ts_rank` and then slug). It
reports where the expected asset landed.

### The synthetic set

`script/search_eval/` holds an invented team wiki of 42 notes (`corpus.yml`) and 28 queries with their answers
(`queries.yml`). Several notes mention another note's topic in passing, so a search that only counts words is tempted
by the wrong one. Run it with no arguments:

```sh
bin/rails folklore:search_eval
```

It loads the corpus inside a transaction that is rolled back, under a `search-eval/` directory of its own, and confines
both searches to that directory, so the rest of the database neither appears in the results nor shifts their order.
Today it scores:

| | recall@10 | top-1 | MRR |
|---|---|---|---|
| baseline | 67.9% | 67.9% | 0.679 |
| current | 96.4% | 89.3% | 0.917 |

`test/lib/search_eval/synthetic_test.rb` pins these numbers, so a ranking change that moves them fails until this
table is updated with it. It is a small set and a regression guard, not a benchmark: 28 queries means one query moves
top-1 by 3.6 points. The current misses are real ones. "how do we roll back a deploy" finds the outage report that
says "rolled back the deploy" and not the rollback runbook, which never uses the word "deploy"; "time off" is mostly
a stopword, so the vacation policy lands sixth.

### Your own set

Your own queries against your own store tell you more than the synthetic set can.

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

The output has one row per query, with its rank in the baseline and in the current search (`#1 of 10`: the answer's rank and how many
results came back, or `--` when the answer is not in the top 10). A summary follows with recall@10, top-1 and mean reciprocal rank. Run it before and
after a ranking change, against the same database.

Every expected slug must be a live asset that is not tagged `eval-excluded`. If one is not, the harness stops and
names the query and slug, rather than counting a typo as a miss.

**`eval-excluded`.** Notes that quote the eval queries, such as a plan or a session checkpoint, match every query
perfectly and bury the real answers. Tag them `eval-excluded` and the harness skips them. Tagging leaves them in
place and searchable as usual.

## The search log

Each MCP `search` with a query records the query, the filters that differ from their defaults, the result slugs and
the token and agent that ran it (the web search page is not logged). When the same token and agent then read one of
those results with `read` or `read_path` within five minutes, the search is marked as followed by that slug. Over time this gives you real queries with the answers people actually
opened, which is the raw material for a bigger eval set. It is a plain table (`search_logs`) and nothing in the app
reads it back.

Nothing prunes it on its own. Delete old rows with

```sh
bin/rails folklore:prune_search_logs        # keeps the last 180 days
bin/rails "folklore:prune_search_logs[30]"  # keeps the last 30
```

and run that from cron if the table grows faster than you mine it. Export the rows you want for an eval set first:
pruning deletes them.
