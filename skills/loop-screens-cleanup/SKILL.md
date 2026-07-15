---
name: loop-screens-cleanup
description: "Sweep the reducer/bug-family screens that `/test/loop_screens` cycles (`.s<N>`, and `.ge<N>`/`.pr<N>`/`newbug` siblings) and end the ones that are done, leaving only screens still actively reducing a reproduced issue. For each ended screen, reap that trial's leftover reducer/subreducer/pquery/mariadbd processes and remove its `/dev/shm/<epoch>` workdir. Decision rule keys off the reducer's `ATLEASTONCE` bracket: `[]` (never reproduced) -> end; `[*]` (reproduced) + finished -> end; `[*]` + still reducing -> leave. Use for the routine \"loop_screens-like cleanup\" of stuck/finished reducer screens."
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# loop-screens-cleanup

Non-interactive batch version of cycling through `/test/loop_screens` and deciding, per screen, end-or-leave. The user normally does this by hand by re-attaching each detached screen in turn; this skill inspects each screen's content via `hardcopy`, applies the decision rule, and ends the done ones cleanly, reaping their resources.

## Inputs

- `<families>` - which screen families to sweep. Default `s`. The `/test/loop_screens*` family map:
  - `s` -> `\.s[0-9]+` reducer screens (the default `/test/loop_screens` target)
  - `ge` -> `\.ge[0-9]+` (`/test/loop_screens_ge`)
  - `pr` -> `\.pr[0-9]+` (`/test/loop_screens_pr`)
  - `newbug` -> screens matching `newbug` (`/test/loop_screens_newbug`)
  Confirm scope with the user when unsure; build/`pts-*`/interactive screens are never in scope.
- `<end-extent>` - how far each end goes. Default `reap` (quit screen + kill that trial's procs + rm its `/dev/shm/<epoch>`). Alternatives: `quit-only` (just `screen -X quit`), `keep-shm` (kill procs but leave `/dev/shm`).

## The decision rule

Each in-scope screen runs a reducer (`bash -c ./reducer<N>.sh ... ; <pge loops> ; bash`). The reducer prints a status bracket at the head of every line - `state::ATLEASTONCE` in `reducercpp/reducer.cpp` (default `[]`, set to `[*]` once the issue reproduces at least once):

```
[ ]                         -> issue NEVER reproduced this run     -> END
[*]  + finished             -> reproduced, reduction complete       -> END
[*]  + still reducing        -> reproduced, actively reducing        -> LEAVE
```

A `[]` screen still showing live subreducer activity is a stuck reducer spinning on a non-reproducing issue (its main reducer is usually already dead, subreducers orphaned to PID 1) - it still ENDs.

Detection signals (per screen, from a `hardcopy -h` dump):
- **bracket** = last `[*]` or `[]` in the dump (default `[]` if none).
- **finished** = last non-blank line is a shell prompt (matches `\$ *$`, e.g. `host:/data/NNN$`) OR the trial's `/dev/shm/<epoch>` has zero live processes.
- **still reducing** = bracket `[*]` AND not finished (live procs, no shell prompt, recent timestamps).

## Procedure

1. **Enumerate in-scope sessions** (full `PID.name` form needed for `screen -S`):

   ```
   screen -ls | grep -oE '[0-9]+\.s[0-9]+'      # adjust regex per <families>
   ```

2. **Hardcopy every session's scrollback** to a scratch dir:

   ```
   mkdir -p /tmp/scdump; rm -f /tmp/scdump/*.txt
   for SES in $(screen -ls | grep -oE '[0-9]+\.s[0-9]+'); do
     screen -S "$SES" -X hardcopy -h /tmp/scdump/"$SES".txt
   done; sleep 0.5
   ```

3. **Classify each screen and extract its dominant epoch.** Take the most-frequent full-length (>=16 digit) `/dev/shm/<epoch>` in the dump as the reducer's own workdir:

   ```
   BRK=$(grep -oE '\[\*\]|\[\]' "$f" | tail -1); [ -z "$BRK" ] && BRK='[]'
   EPOCH=$(grep -oE '/dev/shm/[0-9]{16,}' "$f" | grep -oE '[0-9]{16,}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
   LAST=$(grep '.' "$f" | tail -1)
   PROCS=$([ -n "$EPOCH" ] && pgrep -cf "/dev/shm/$EPOCH" || echo 0)
   if echo "$LAST" | grep -qE '\$ *$' || [ "$PROCS" = 0 ]; then FIN=yes; else FIN=no; fi
   if [ "$BRK" = '[*]' ] && [ "$FIN" = no ]; then DECISION=LEAVE; else DECISION=END; fi
   ```

   Build the **PRESERVE set** = the epochs of every `LEAVE` screen. These must never be killed or removed.

4. **Show the plan and reap.** Present the END/LEAVE table first, then for each `END` screen with `<end-extent>=reap`:

   ```
   MYPID=$$
   # pass 1: kill that trial's procs (skip PRESERVE epochs and own PID)
   PIDS=$(pgrep -f "/dev/shm/$EPOCH" | grep -vx "$MYPID")
   echo "$PIDS" | xargs -r kill -9
   sleep 2
   # pass 2 (straggler sweep): children reparented to PID 1 survive a parent SIGKILL
   pgrep -f "/dev/shm/$EPOCH" | grep -vx "$MYPID" | xargs -r kill -9
   # remove the trial's shm workdir, then quit the screen
   [ -d "/dev/shm/$EPOCH" ] && rm -rf "/dev/shm/$EPOCH"
   screen -S "$SES" -X quit
   ```

5. **Verify:**

   ```
   screen -ls | grep -oE '[0-9]+\.s[0-9]+'                          # only LEAVE screens remain
   pgrep -fc '/dev/shm/<preserve-epoch>'                            # LEAVE reducer still alive
   ls -d /dev/shm/<preserve-epoch>                                  # LEAVE shm intact
   pgrep -af '<reaped-epoch>' | grep -iE 'mariadbd|subreducer|pquery'   # expect none
   ```

   A residual `pgrep` match on a reaped epoch whose only hits are `bash` with parent PID = `claude` is the agent's own tool processes echoing the epoch on their command line - a false positive, not reducer waste. Confirm by filtering for `mariadbd|subreducer|pquery`.

## Constraints

- Kills and `rm -rf /dev/shm/<epoch>` are pre-authorised only for epochs owned by an `END` screen. NEVER touch a PRESERVE-set epoch.
- Always exclude the agent's own PID (`$$`) from kills, and match the full epoch path (`/dev/shm/<19-digit>`) so a partial digit-run can never collide with a PRESERVE epoch.
- Out of scope: `/dev/shm/178*` reducer dirs with **no owning screen** and zero live procs. These are orphan leftovers from reducers whose screens are already gone; report them with a size total and let the user decide - do not delete unprompted. A wholesale `/dev/shm` wipe is `~/ka` territory and is user-only.
- Build screens (`opt_and_dbg_build`, `*_san_build`), `pts-*` interactive shells, and ad-hoc named screens (`memory`, `my_cleanup_script`, `ds_r_o`) are never ended by this skill.

## Try-harder reproduction before ending a `[]` screen

A `[]` screen means the reducer never reproduced the original `MYBUG` this run - usually because the issue is sporadic, build-specific, or needs many threads. Before ending it for good, an optional reproduction pass is often cheap and worthwhile. Full method catalogue: `~/mariadb-qa/reproducing_and_simplification.txt`. The framework-native "try harder" relaunch:

```
cd <workdir>                       # e.g. /data/721369
# methodology levers for a non-reproducer (reducer<N>.sh):
sed -i -E 's/^FORCE_SKIPV=0/FORCE_SKIPV=1/;        # skip verify -> straight to MULTI stage 1 churn
           s/^FORCE_SPORADIC=0/FORCE_SPORADIC=1/;  # treat as sporadic (auto-set by FORCE_SKIPV)
           s/^MULTI_THREADS=3\b/MULTI_THREADS=6/;   # more parallel reproduction attempts
           s/^MULTI_THREADS_MAX=9\b/MULTI_THREADS_MAX=12/' reducer<N>.sh
rm -f <workdir>/<N>/17* <workdir>/<N>/*_out*       # pre-sr cleanup; KEEPS the original *thread-0.sql trace
~/sr <N>                                            # relaunches as a detached screen s<N>, churning on the ORIGINAL trace
```

`reducer<N>.sh`'s `INPUTFILE` already selects the original `default.node.tld_thread-0.sql` (it excludes `failing`/`prev`/`backup`), so the relaunch replays the full recorded trace, not the collapsed `_out`. Keep total concurrent subreducers in check: ~6 threads x N reducers; watch `uptime` load and `df -h /dev/shm` (raising `MULTI_THREADS` to 25-40 can overload the box / fill shm).

Locate a trial's workdir(s) with `ls -ld /data/*/<N>` (trial numbers repeat across pquery-run sessions); when several match, disambiguate by the epoch in `<workdir>/reducer.logs/reducer<N>.log`. Triage each `[]` screen from its `MYBUG` signature (`<workdir>/<N>/MYBUG`) before spending effort:

```
SAN (UBSAN|... / ASAN|...)        -> trace-replay on the SAN build (the reducer auto-uses MYBASE); FORCE_SKIPV churn.
                                     First cross-check ~/kb / ~/kbs (known_bugs.strings[.SAN]) - frame match may be a known/fixed MDEV.
ASSERT|<cond> with NO frames      -> nts/gdb did not resolve. Check <N>/log/*.err for the real assert line + source:line,
                                     or re-run ~/tt in the trial dir to rebuild the full UniqueID before reducing.
MARIADBD_ERROR / INNODB_ERROR     -> typed error-log item ("end of the road"): often data/timing/recovery dependent.
                                     Read the emit site in /test/<ver> source to learn the trigger, then craft targeted SQL.
concurrency race (signature hints:   -> the default relaunch replays each subreducer SINGLE-THREADED (pquery --threads=1), so a
  ALTER ... REORGANIZE/REBUILD          race between concurrent sessions can NEVER reproduce no matter how many subreducers or
  PARTITION, racey DDL/DML asserts)     how dense the trace. Set PQUERY_MULTI=1 in reducer<N>.sh (auto-enables USE_PQUERY;
                                        runs PQUERY_MULTI_CLIENT_THREADS=30 concurrent clients per subreducer = true concurrent
                                        replay). Use the original trace (concurrency, not density, is the trigger), then ~/sr.
INNODB_ERROR ...recovery/undo...  -> crash-recovery corruption. Locate the trial's saved datadir with `ls -ld /data/*/<N>`
                                     (lists every workdir holding trial <N>). If <workdir>/<N>/data is populated
                                     (undo001 / ibdata1 / ib_logfile* present), reproduce by starting the MYBASE build's
                                     mariadbd on it: --datadir=<workdir>/<N>/data (the {epoch}_start script already does this).
                                     If data/ is empty (a /dev/shm run, cleaned post-trial) and no {epoch}_bug_bundle.tar.gz
                                     exists, the corrupt state is lost -> low tractability; only a trace replay that re-crashes
                                     then restarts can recreate it.
```

When the relaunched reducer reproduces, it auto-minimises to a short testcase. When it stays `[]` after a good churn, fall back to the catalogue (`PQUERY_MULTI=1` concurrent replay for race bugs, double/triple-cat the trace, `USE_PQUERY=0` CLI replay, `MODE=4` any-crash, source-guided hand-crafted SQL) or end the screen and record the signature + best next step.

## Related rules / references

- `~/mariadb-qa/reproducing_and_simplification.txt` - full catalogue of reproduction and simplification techniques for non-reproducers.
- `reducercpp/reducer.cpp` - the `ATLEASTONCE` bracket, RUNMODE, and subreducer model behind `[*]` vs `[]`.
- `~/kb` / `~/kbs` cross-check a `[]` signature against `known_bugs.strings[.SAN]` before reducing.
- `~/ka` (mass kill plus a `/dev/shm` wipe) is user-only; this skill is the surgical, scoped alternative.
- To stop a live-attached reducer by hand: `Ctrl+C x 3` then `depge`.
- Before a `~/sr` relaunch, clear the trial dir: `rm 17* *_out*`.
