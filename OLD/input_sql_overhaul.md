# SQL input overhaul: sources only, no PRE_SHUFFLE

Turn the SQL input into four sources with per-source settings. Drop `PRE_SHUFFLE_SQL` and the
regeneration cadence for the two fast generators. The assembled file is filtered once and shuffled
once, so the SQL of each source is spread over the whole file.

## The new model

```
  sources                                     assembly (every trial)          runtime
 ┌──────────────────────────────────────┐    ┌──────────────────────────┐   ┌──────────┐
 │ USE_GENERATOR=1    every trial       │    │ concatenate in order     │   │ pquery   │
 │ USE_REVGEN=1       every trial       │───>│ clean-up sed             │──>│ reads    │
 │ USE_INFILE=1       whole file, or a  │    │ ADV_FILTER_SQL (opt)     │   │ the file │
 │                    random window     │    │ cut at MAX lines         │   └──────────┘
 │ USE_ALL_DISK_SQL=1 cached index,     │    │ FILTER_SQL (opt)         │
 │                    own cadence       │    │ shuffle                  │
 │                                      │    │ transforms               │
 │                                      │    │ final cut at MAX lines   │
 └──────────────────────────────────────┘    └──────────────────────────┘
   share of each source = its line count      one file: TRIAL_SQL
```

## Old to new mapping

| Old | New |
|---|---|
| `PRE_SHUFFLE_SQL=0` | nothing; the active sources are the input |
| `PRE_SHUFFLE_SQL=1` | `USE_INFILE=1`, plus `ADV_FILTER_SQL=1` |
| `PRE_SHUFFLE_SQL=2` | `USE_ALL_DISK_SQL=1`, plus `ADV_FILTER_SQL=1` |
| `PRE_SHUFFLE_TWO_MIN_SQL_LINES` | `QUERIES_PER_ALL_DISK_RUN` (exact, no overshoot) |
| `PRE_SHUFFLE_TRIALS_PER_SHUFFLE` | `ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS` |
| `PRE_SHUFFLE_DIR` | `TRIAL_SQL_DIR` |
| `PRE_SHUFFLE_INTERLEAVE*` | `INTERLEAVE*` |
| `GENERATE_NEW_QUERIES_EVERY_X_TRIALS` | gone, the generator runs every trial |
| `REVGEN_NEW_QUERIES_EVERY_X_TRIALS` | gone, revgen runs every trial |
| `shuf -n MAX` over a big INFILE | random byte window of the INFILE, same size |
| ADV filter tied to the shuffle modes | `ADV_FILTER_SQL=0/1`, set per conf to what it does today |
| transforms only on PS=1/2 | transforms on every source combination |

Measured evidence behind this: pquery gets no `--no-shuffle` on any trial invocation; generator
100k queries = 0.06 s, revgen 200k = 1.08 s; `shuf -n` sampling 2M of 10M lines = 2.93 s and 345 MB
RSS against 0.07 s and 3 MB for a byte window; the all-disk `find /` walk = 16.1 s of the 101 s a
collection took, and the rest is per-file reads plus an O(n^2) `wc -l` on the growing pool.

## Results

| | Before | After |
|---|---|---|
| All-disk collection, 20,000 lines | 101 s | 1 s, after a 15-21 s index once per run |
| Per rebuild of a combined file with a 1.4 GB INFILE | 1.4 GB written, cut to 290 MB | 290 MB written |
| Generator and revgen | new SQL every 10 to 40 trials | every trial (0.06 s / 1.08 s) |
| Sampling a large INFILE per trial | first N lines, the same every trial | random window, 0.07 s |
| Transforms | only with PRE_SHUFFLE_SQL 1 or 2 | every source combination |

## Pre-existing, todo

- `pquery/pquery-cluster.cfg` carries a hardcoded `infile`, and the multi-threaded Galera path copies
  that template without substituting it, so that path has never used the framework's SQL sources.
