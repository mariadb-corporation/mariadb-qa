---
name: bug-fix-post
description: Turn a MariaDB Jira bug ticket (MDEV/MENT) into a candidate source fix delivered as fix.diff. Read the ticket through the Jira PAT so developer-only comments come along, reproduce every testcase in the ticket on a baseline build, work out the root cause with help from the full clone in /test/git-bisect/<ver>, patch and build a /tmp copy of /test/<ver>, then prove the fix on every testcase and on an MTR regression run, and post it to the ticket in the house format. Use whenever a fix is wanted for a bug ticket that already exists. A fix is always the deliverable here, and the ask comes in many forms - "bug fix please", "fix this bug", "produce a fix", "iterate the fix", "deliver fix", "1/2/3", "1/2/3/4", "gate 1/2/3", "gate 1/2/3/4", "gate fix/pass/diff/base". Every reply that reports on the fix carries the four-gate command block, until the comment is posted. Started without a ticket key? Ask which bug, and never go looking for one. For a bug not yet filed, use jira-ticket instead.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater. Keep skills/README.md (the skills index) in sync when any skill is added, renamed, removed, or its description changes.
---

# bug-fix-post

A bug ticket in, a reviewed `fix.diff` out.

## First - which bug?

**Given a ticket? Start. Not given one? Ask, and stop there.** When the skill starts with no
ticket key, URL or other pointer to one specific bug, the whole procedure below is on hold,
the session rename included. Ask one short plain question - which bug should be fixed - and
wait for the answer. Plain text, not a clickable question.

Do NOT go looking, in any form: no Jira search, no sweep of the assigned tickets, no
"In Testing" list, no listing of `/data`, no picking a bug out of earlier session work.
Loading this skill, alone or beside another bug skill, is not an instruction to start. The
user knows which bug they want fixed, and a search picks the wrong one while spending tokens.

## Inputs

- The ticket key or URL (MDEV-... / MENT-...).
- The target branch. Default to the earliest maintained branch the ticket affects. For CS that is 10.11, so a 10.6 fix is not expected.

## Name the session first

Rename the session and the screen it runs in, so this work is easy to pick out in `~/s`
and on the status line. The name is `bug-fix-<KEY>`:

```
python3 ~/mariadb-qa/claude/rename_session.py bug-fix-MDEV-12345
```

For a bug that has no ticket yet, take the next free number:

```
N=$( { grep -ho '"name":"bug-fix-NEW-[0-9]*"' ~/.claude/sessions/*.json; screen -ls; } 2>/dev/null | grep -o 'bug-fix-NEW-[0-9]*' | sed 's/.*-//' | sort -n | tail -1 )
python3 ~/mariadb-qa/claude/rename_session.py "bug-fix-NEW-$(( ${N:-0} + 1 ))"
```

The script does both renames and reports each on its own line. First the session name,
which `~/s` shows in the CLAUDE INT column and the status line carries as its last field.
Then the screen, through `~/sren`. The two are independent, so a session that cannot write
its own name still gets its screen renamed, and a session outside a screen gets the name
only. Rename again once the bug has a key.

## Procedure

### 1. Read the ticket with the Jira PAT

A web fetch shows only public comments. The REST API with the PAT also returns the
developer-only ones. The token comes from `$JIRA_PAT` or
`~/.config/mariadb-qa/jira.pat`. The `jira-ticket` skill says how to create one.

```
PAT=${JIRA_PAT:-$(cat ~/.config/mariadb-qa/jira.pat)}
curl -s -H "Authorization: Bearer $PAT" \
  "https://jira.mariadb.org/rest/api/2/issue/<KEY>?fields=summary,description,status,priority,components,versions,fixVersions,labels,comment,issuelinks"
```

Read the work log too, at `/rest/api/2/issue/<KEY>/worklog`, where anyone may have left
additional comments.

Collect every testcase, from the description and from each comment. The later comments
usually hold the smallest testcases and the extra variants, and each variant is part of
the job.

Also collect what the developers have said about the cause and about the right fix. Look for
it in the linked tickets too, and in each ticket that a developer comment names. Step 3c says
how the fix follows it.

### 2. Reproduce first

Copy a built basedir for the branch to /tmp, rebake it, and run each testcase in a fresh
instance. Never run in a /test basedir.

```
cp -r /test/<basedir> /tmp/<basedir>
cd /tmp/<basedir> && ~/st
cd /tmp/<basedir> && ./anc && cp <testcase>.sql in.sql && ./test
```

- Detect a crash by the presence of `data/core`. The error log often carries no stack.
- `~/stack` run from the basedir prints the stack. Check it against the one in the ticket.
- Before building a baseline, check whether an existing basedir will do. Compare the
  affected functions at both commits and reuse the old build when they match.

```
git show <commit>:sql/<file>.cc | sed -n '/^<function>/,/^}/p' | md5sum
```

### 3. Find the root cause

`/test/git-bisect/<ver>` is a full clone. Read it, never edit it. The `/test/<ver>` trees
are shallow, so the history lives only there.

```
cd /test/git-bisect/<ver>
git log --oneline -S "<symbol>" -- sql/<file>.cc
git show <sha>
```

An earlier fix in the same area usually shows the in-house pattern to follow, and its
helper code is often the piece your fix should reuse.

### 3b. Whose code is it - ours or a third-party library

Once the root cause is pinned, check whose code holds it. The server bundles a few
genuinely third-party libraries - WolfSSL, PCRE2 and zlib - and the root cause can sit
in one of them. Most other bundled code is ours, so a defect there is an ordinary fix.

- **Solely in the library.** Our code calls the library the documented way and the
  library answers wrongly. There is nothing in our tree to patch, so a `fix.diff` is
  the wrong deliverable. Say so on the ticket and open an issue in that project's own
  tracker (all three take GitHub issues). Filing upstream is not a developer-only task
  - a tester files there directly.
- **Ours, at the boundary.** The library is correct and we use it wrongly, or the
  server can hold the line itself whatever the library does: an option that never
  reaches the library, an unchecked length before the call, a check we own. Patch it
  and carry on with step 4.
- **Both.** The library should change and we can also guard. Deliver our guard as the
  fix and open the upstream issue for the library, each referencing the other.

How to tell them apart: build the same source two ways where you can, one against the
bundled library and one against the system one, and run the testcase on both. A failure
on one build only points at the library. A failure on both points at our code.

### 3c. Fix the cause, not the symptom

The crash, the assert or the error is where the bug shows. The cause is the earlier step that
put the server in that state. The fix goes at the cause, so that the bad state never occurs,
and everything the statement touches is correct afterwards: the rows, every index, the binlog,
a replica and the state after a restart.

None of these is a fix. Each one hides the bug and leaves the cause in place:

- An assert that is removed, relaxed or widened so that it no longer fires.
- An assert turned into an error-log message or a warning. The user can do nothing about it.
  If the assert was right, the problem remains. If it was wrong, the message is as false as
  the assert.
- An error code that is dropped: `std::ignore`, a `(void)` cast, a return value that nothing
  reads.
- An early return, a NULL check or a skip that stops the crash and leaves the work undone.
- Any change after which an index, the binlog or a replica does not match the table data.

**An assert stays, unless the fix removes the code it checks, or you prove it wrong.** When it
catches a real problem, keep it and fix the problem. When it is wrong, the state it rejects is
valid. Prove that every later step handles that state correctly, then remove the assert and
put nothing in its place: no error message, no warning.

**Follow the developers' direction.** Read what step 1 collected, and the code comments near
the fault: a `FIXME`, a `TODO` or an MDEV number there often names the real fix. Where a
developer has given the cause or the way to fix it, the fix follows that direction. Where the
code shows that the direction cannot work, prove it with a testcase and give that in the reply.

A comment that calls the proper fix hard, or says it needs a redesign or months of work, sets
the size of the job. It is not a reason to patch the symptom. Do the proper fix. Keep it as
small as a correct fix can be: no hunk outside the fix, and never less than the whole fix.

**A fix that needs an excuse is not done.** When the comment needs words such as `the fix
stops the crash only`, `afterwards the index does not match the table` or `up to you whether
the fix is worth having in the meantime`, go back to step 3. Never post such a fix. When three
full rounds do not give a correct fix, post nothing. Tell the user what each round changed and
what blocks the proper fix, with the evidence.

MDEV-24608 comment 340697 shows what not to post. It dropped the assert, logged an error that
the user cannot act on, and left the full-text index not matching the table.

### 4. Know the right answer before you patch

Find a form of the statement that means the same thing and already works, run it on the
baseline, and keep its output as the reference. A crash fix that returns a wrong answer is
not a fix. Compare the two forms again after the fix.

When the bug shows on one build flavour only, the other flavour is the reference. Pair
every testcase, the quiet build against the patched one, and require identical output.

When the evidence contradicts your reading of the code, go and check it. A breakpoint
with a printf on the live server settles in one run what reasoning will not.

**Cover every code path, before you write the patch.** The testcase reaches the broken code
down one path. Other paths reach it too, and a fix on one of them leaves the bug in place on
the rest. `Still need to fix three other calling sites` is not a follow-up item, it is the
same fix unfinished.

Enumerate first, then patch. Search the whole tree, not only the file you are in:

```
cd /test/<ver>
/bin/grep -rn "<function or broken expression>" \
  --include=*.cc --include=*.h --include=*.ic .
```

Three things that search has to turn up:

- Every caller of the function you change. Which of them reaches the same bad state?
- Sibling code of the same shape: a copy-pasted block in a neighbouring engine, or a
  second overload.
- The other entry points to the same state: prepared statements, a stored routine, the
  binlog or replication path, a background thread, recovery, shared client code.

Fixing at the lowest common point beats fixing several callers, but only when that point is
the right place for the check. Say in one line which you chose. For a call site that needs
nothing, say why not - it already holds the lock, it cannot carry a NULL, etc.

### 5. Patch and build a /tmp copy

Mechanics are in `build-fix-diff`. In short:

```
cp -r /test/<ver> /tmp/<ver>_fix_<KEY>
# edit /tmp/<ver>_fix_<KEY>/sql/...
cd /tmp/<ver>_fix_<KEY> && ~/mariadb-qa/build_mdpsms_dbg.sh
cd /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-dbg && ~/st
```

`ba` builds opt and dbg. One `build_mdpsms_dbg.sh` is enough while iterating; add the opt
build for the final check.

After the first full build, iterate faster: copy the changed sources into the build dir the
script left behind, rebuild the server alone, and drop it into the basedir.

```
cp -p /tmp/<ver>_fix_<KEY>/sql/<changed> /tmp/<ver>_fix_<KEY>_dbg/sql/
cd /tmp/<ver>_fix_<KEY>_dbg && make -j40 mariadbd
cd <basedir> && ./kill && cp /tmp/<ver>_fix_<KEY>_dbg/sql/mariadbd bin/mariadbd
```

Before you hand the diff over, check that the source copy and the build dir hold the same
bytes, so the binary you tested is the one the diff describes.

### 6. Prove it

- Every testcase from the ticket: no crash, and output equal to the reference form.
- The end state, not only the crash. When the bug changes data, read back the rows after each
  testcase, and each index through a query that uses it. Rebuild the table with
  `ALTER TABLE ... FORCE`, run the same queries again, and require the same results. Where the
  bug touches them, check the binlog, a replica and the state after a restart as well.
- For a change in commit, rollback or recovery code, also run `ROLLBACK`, `XA PREPARE` then
  `XA COMMIT`, `XA PREPARE` then `XA ROLLBACK`, and a restart between `XA PREPARE` and
  `XA COMMIT`. Where the commit runs in more than one step, kill the server between the steps
  (a gdb breakpoint, then `kill -9`) and check the state after the restart. A prepared
  transaction must commit without error, so nothing that can fail may run after `XA PREPARE`.
- Regression: run a handful of MTR tests that cover the changed code, on the patched build
  and on the baseline build, then diff the two failure lists. A full suite run is not
  wanted, the `main` suite included.
- Probe around the fix with your own variants, and run them on both builds. Variants the
  ticket never listed are where the next crash sits.
- Every path the step 4 sweep listed gets its own or combined run: a testcase per reachable
  site, on both builds. Where a site cannot be reached from SQL, say so in one line and say
  why, rather than leaving it untested and unmentioned.
- Keep each statement on one line. `mysqlbinlog` wraps its base64 at 76 columns, so join
  a `BINLOG '...'` block into a single line before it goes in a `.test`.
- Gate on `--die`, never on `include/assert.inc` and never on a bare error code. An
  `assert.inc` failure reads `Test assertion failed` in an included file, which names
  nothing. Write the `--die` text as one plain-English sentence naming the bug, and start
  it with plain words, never with an SQL keyword: `The new partitioned table exists on
  node 1 but not on node 2. It was not replicated to the cluster.`, not `CREATE TABLE AS
  SELECT on a partitioned table was not replicated`, which reads as a query.
- Prove every gate. A later gate is unreachable once an earlier one dies, so flip its
  expected value on the patched build once, confirm the die fires and reads well, and
  restore it.
- Read the MTR summary to the end. `Completed: All 1 tests were successful` can sit right
  below a failed post-test check, so the last line alone is not the verdict.
- A testcase that needs `INSTALL PLUGIN` does not belong in the main suite. The install
  creates the plugin's own tables and functions in the `mysql` schema, and MTR compares
  that schema after every test, so the run ends in `Check of testcase failed` even though
  the test body passed. Put it in the plugin's own suite instead, copy the setup and
  teardown from a neighbouring test there, and name it after the ticket. For Spider that
  is `storage/spider/mysql-test/spider/bugfix/t/mdev_<number>.test`, and in a basedir the
  suite sits under `mysql-test/plugin/spider/spider/`, so it runs as
  `./mtr spider/bugfix.mdev_<number>`.

#### The four gates

The test that goes in the ticket comment is the one that went through these gates, byte
for byte. Put every ticket testcase in one MTR test, copy the `.test` into both
basedirs, and run all four. Verify it in the main suite as `main/test_claude`.

Never use a `.result` file. Do not record one, do not copy one, do not gate on one, do not
deliver one. MTR runs a test without one and prints its output, so the `--die` gates in
the test carry the verdict on both builds. A developer records the result on their own
fixed tree.

1. Original must fail. Run the test on the baseline basedir. It has to fail there, on
   the symptom the ticket describes: the stack, the error, the wrong result, the hang,
   the lockup, or other bug. A pass here means the test does not detect the bug.
2. Fixed must pass. Run the same test on the patched basedir. It has to pass, with the
   MTR summary read to the end.
3. Same test on both sides. Diff the `.test` between the two basedirs. It must be empty.
   Without this a silent copy failure reads as a fix, and a comment that shows a test
   other than the one that ran proves nothing.

```
diff <baseline basedir>/mysql-test/main/test_claude.test \
     <patched basedir>/mysql-test/main/test_claude.test
```

4. Same base on both sides. The baseline and the patched build must come from the same
   source, differing only by `fix.diff`. The version string alone does not settle it: two
   basedirs can both read `13.1.0` and be weeks apart, and then an upstream fix in between
   reads as your patch working. The version and the exact revision must be identical on
   both sides, so read this before you read any other gate result:

```
cd <baseline basedir>
source ~/mariadb-qa/version_chk_helper.source
echo "$SERVER_VERSION $SOURCE_CODE_REV"
cd <patched basedir>
source ~/mariadb-qa/version_chk_helper.source
echo "$SERVER_VERSION $SOURCE_CODE_REV"
```

   Two different lines means gates 1 and 2 compare apples with oranges and prove nothing.
   Build the baseline unpatched from the same source copy the patch came from. An older
   basedir lying around in `/tmp` or `/test` is not a baseline; it is a different tree.

   Never pair an Enterprise Server build with a Community Server build across gates 1 and
   2. They are two different products, so the pass side proves nothing about the fail
   side. Where the bug sits in Enterprise Server code, both sides are Enterprise Server
   builds; where it sits in Community Server code, both sides are Community Server
   builds. The same holds for any other cross-product pair, MySQL among them.

   A build that never carried the affected code is not a gate 2 side either. Its pass is
   settled before the run, so it shows nothing.

Where you need the history between two revisions - to see whether the asserting file changed
at all - remember the `/test/<ver>` trees are shallow, so `git log <old>..<new>` there fails
with an invalid revision range. `/test/git-bisect/<ver>` holds a full clone for the CS
branches. For a branch with no full clone, an ES branch among them, take a deep clone of that
branch and read the history there.

All four have to hold before there is a result. One that does not sends the work back to
the testcase or to step 5, never on to the comment. The four headers of the paste block
in step 7 are these four gates, in this order.

### 7. Deliver

Every outcome file goes in `${HOME}/<KEY>/`, for example `~/MDEV-27903/`. Create
that directory and write `fix.diff`, the `.test` and the ticket comment there. No
`.result`. Never leave an outcome in `/tmp` or in the session scratchpad; both are ephemeral,
so a deliverable written there is lost. Only the working trees stay in `/tmp`: the source
copy and the patched basedir.

`git diff` inside the /tmp copy gives `fix.diff`; copy it into `${HOME}/<KEY>/`. Source
only. No `.test` or `.result` files, no unrelated cleanups, no cosmetic whitespace.

Keep the /tmp source copy and the patched basedir. List their absolute paths at the end and
let the user say when they go.

**Reply shape.** Every reply that reports on the fix looks like this, in this order:

1. One line with the bottom line, such as `The fix holds: all three testcases pass with it.`
2. Short bullets, 15 words or fewer: ✅ for a check that holds, ⚠️ for a real gap or risk,
   🔵 for what changed since the last reply.
3. The bug details in a plain fence, one field per line, values aligned. `Severity` and
   `Priority` are always there, right under the ticket. `Severity` says in a few plain
   sentences what the bug does to the user, and what it does not do, such as `No crash.`
   `Priority` is the priority the ticket has now.

   ```
   Ticket      MDEV-NNNNN, <title>
   Severity    Wrong result: the index finds no row, a table scan finds 3. No crash.
   Priority    Major
   Cause       <file:line>, <what is wrong, in a few words>
   Fix         <file(s) changed>, <what the patch does, in a few words>
   Testcases   <n> of <n> fail on the baseline, pass on the patched build
   Regression  <suites or tests>, <count>, the same on both builds
   ```

4. A ```bash fence with one `cat ${HOME}/<KEY>/comment.txt` line, the path in full, and
   nothing else, as the first lines after the bug details fence. No `-` in front of a
   path, and never the other files. Nothing goes between the two fences but one blank
   line: no question, no label. A genuine open fork, if there is one, goes in the bottom
   line.
5. The four-gate block, always last.

Never paste an artifact into the reply, the testcase included; name it by its path.

Put the MTR command lines in the body of every reply that reports on the fix, in one
paste-ready fenced `bash` block so the headers render green, split by the four gate headers `# Original (gate 1, must
fail):`, `# Fixed (gate 2, must pass):`, `# Diff (gate 3, must be empty):` and `# Base
(gate 4, must be identical):`. Full
absolute paths, no placeholders. The
`# Diff` part carries the gate 3 command from step 6, so the reader can confirm both trees
hold the same test before reading anything into the two outcomes, and the `# Base` part
carries the gate 4 command, so they can confirm both trees sit on the same version and
revision. All four parts go in the one block; a diff quoted only in the prose above is
not the block.

**Never split a command line without a trailing `\`.** Each command is one line, or every
line that continues ends with a backslash. Wrap without it and the second half runs as its
own command, so the paste fails.

The terminal wraps any line past its width on its own, and that wrap carries no backslash,
so a line the reader copies off the screen is already broken. Keep every line in the block
at 80 characters or under, and split anything longer yourself with a trailing `\`, indenting
the continuation two spaces. Split between two words only, never inside a path.
Count the characters on every line of the block before you post it.

**Gate 3 is one plain `diff` of the two test files, as in the template below.** `T` holds
the tail the two test paths share, so each `diff` line is just a basedir plus `/$T` and fits
the window. No `cd` per side, no `md5sum` and no `cmp` in gate 3.

**Never put a parenthesised subshell in the block.** A multi-line `( cd ... \` construct
does not survive a paste: the terminal mangles it and bash answers
`syntax error near unexpected token '('`. Gate 4 therefore uses six plain lines, `cd`,
`source`, `echo` per side, each one a complete command with no backslash and no brackets.
The helper reassigns both variables every time it is sourced, so the second side cannot show
a stale value from the first. Prefer that shape anywhere else in the block too: short
standalone lines beat one clever line.

The four-gate block goes in every later reply that reports on the same fix, unchanged and
complete, however small the change, so the reader can re-run all four gates from the reply
in front of them. A reply about anything else leaves it out, such as a side bug found while
probing or a ticket filed for it. Those gates do not test that work, so there the block
reads as the gates for the wrong bug. Once the comment is posted, later replies leave the
block out as well.

**Never ask a clickable question.** The `AskUserQuestion` tool is out for the whole of this
skill. No blue question card, no proposed answers, no menu. That holds hardest for the reply
carrying the four-gate block: the block is the last thing in that reply, and nothing follows
it - no `Shall I post it?`, no `Ready for gate 2?`. Where a genuine fork is open, write it as
one plain sentence above the block and stop there. Where you can decide it yourself, decide
it and say what you chose in one line.

**Do the whole job before you reply.** A question is usually a piece of work handed back, so
do the work instead. Every reply is a complete deliverable: the fix built, every testcase
run, all four gates proven, the comment file written and its path given. A reply that says
`let me know and I will do X` should have done X. The only thing left for the user is the
go-ahead to post.

**Each gate stands on its own.** Any variable a gate uses is assigned under that gate's own
header, so one header plus the lines below it can be copied and run by itself. A gate
assigns only its own variables: gate 1 sets `S`, gate 2 sets `F` and `L`, gate 3 sets `T`,
and gate 4 uses none, it writes both paths out in full. Never open the block with a shared `S=`/`F=`
preamble above the headers: that makes the reader copy two pieces to run one gate, and they
have said so. `L` holds the regression test list. A long list goes on more `L="$L ..."` lines,
never on `\` lines: a space the copy adds after a `\` breaks the command.

```bash
# Original (gate 1, must fail):
S=<baseline basedir>
cd $S/mysql-test && ./mtr main.test_claude

# Fixed (gate 2, must pass):
F=<patched basedir>
cd $F/mysql-test && ./mtr main.test_claude
L="<the relevant tests>"
cd $F/mysql-test && ./mtr --parallel=<n> --force $L
cd $F/mysql-test && ./mtr --parallel=<n> --force --ps-protocol $L

# Diff (gate 3, must be empty):
T=mysql-test/main/test_claude.test
diff <baseline basedir>/$T \
     <patched basedir>/$T

# Base (gate 4, must be identical):
cd <baseline basedir>
source ~/mariadb-qa/version_chk_helper.source
echo "$SERVER_VERSION $SOURCE_CODE_REV"
cd <patched basedir>
source ~/mariadb-qa/version_chk_helper.source
echo "$SERVER_VERSION $SOURCE_CODE_REV"
```

The test directory is `mariadb-test` on 11.4 and newer and `mysql-test` on 10.11, so use the
one the basedir has.

Under each `./mtr` command, quote the line that decides its verdict as a `#` comment, as it
came out: the `--die` text or `Completed: All 1 tests were successful.` for gates 1 and 2,
the summary line for a regression run. Under gate 4, one `#` line with the version and the
revision. A quoted line longer than 80 characters goes over two `#` lines.

For a suite test, the path is `mysql-test/suite/<suite>/t/<test>.test`. A galera test needs
`WSREP_PROVIDER` set, and in a command block handed to the user it goes on its own line, with
`export`, never as an inline prefix on the `./mtr` line:

```bash
cd <basedir>/mysql-test
export WSREP_PROVIDER=<provider .so>
./mtr galera.<test>
```

A long inline-prefix line wraps in the terminal, and the pasted second line then reads as a
plain shell assignment, which `./mtr` does not inherit. The run reports
`[ skipped ]  No wsrep provider library`, and a skip reads as a clean pass. Check the run said
`[ fail ]` or `[ pass ]` and not `[ skipped ]`.

### 8. Post it to the ticket

Check the ticket status first. Where the ticket is closed, a new defect or an incomplete
pushed fix goes in a new bug report through `jira-ticket`, with the closed ticket named as
the cause in a link.

Who fixes it: if someone's patch introduced the bug, that person fixes it. Otherwise it is
most often the owner of the area. The patch author is the assignee of the ticket that patch
was for, the one the "is caused by" link names; confirm the account is active. Address the
closing line of item 8 below to that person. Example: MDEV-41480 went to the assignee of
MDEV-40362, whose patch introduced it. Post to a closed ticket only where the user has said in so many words
to post to that ticket.

Never put the `contribution` label on a bug, new or existing, not even when the feature
ticket or its sibling bugs carry it.

In a new report that follows on from another ticket, the opening line names it:
`I've evaluated MDEV-<n>.`, never `I evaluated the pushed fix`, which reads as a
comment on the old ticket.

Write the whole comment to a paste-ready `${HOME}/<KEY>/comment.txt`. Every mention of
that file in the reply carries its full absolute path, every time, including the
sentence that proposes posting it. Never write the bare name `comment.txt`, and never
`the comment file`: the reader opens it from the reply, so a name without a path is a
dead link. The same holds for `fix.diff` and the `.test`. Nothing reaches the ticket
without approval, and that covers a comment, a link and a version field alike. Propose it
and wait. Propose it in one plain sentence, never as a clickable question.
Jira wiki markup, in this order. SQL keywords and data types go in UPPERCASE
throughout - `{{UUID}}`, `{{VARCHAR}}`, `{{FOREIGN KEY}}`, never `{{uuid}}` or
`{{varchar}}`, even where the source or the reporter's DDL writes them lowercase.
Identifiers keep their real case. See `~/mariadb-qa/skills/_shared/jira_markup.md`.

Once approved, post it from the file:

```
~/jira --comment <KEY> --description-file ${HOME}/<KEY>/comment.txt
```

`--description-file` reads the file. `-d` takes the comment text itself, so `-d <file>`
posts the path as the comment. The script refuses a body that is one line or starts
with `/` for that reason, and `--oneline` is the override for a body genuinely meant to
be one line. Read the `=== Body ===` block the script echoes before confirming.

Try deleting before rewording. When a sentence reads wrong, cut it and read the
paragraph without it. Very often nothing is lost, because the sentence was a lead-in,
a framing line or a restatement, and the paragraph is better starting on the fact.
Reword only what survives the cut.

**A fix comment on a ticket filed in the same session is the short form, not the nine
steps below.** That description already carries the root cause, the testcase and the
matrix, so repeating any of it wastes the reader's time. Four parts, nothing else:

1. `AI (<model>, <effort> effort) proposed fix:` then a blank line.
2. `{code:cpp}` with the whole `fix.diff`.
3. The evidence that the fix does what it claims, under one sentence saying where the
   numbers come from. A before and after of the two values the bug is about beats any
   description of them.
4. One sentence with the gate result: how many runs fail on the baseline and how many
   pass patched.

Nothing else goes in. No regression-test list, no build provenance, no same-revision
sentence, no control-case aside. Those belong in the reply to the user, and they get cut
from the comment every time. When a supporting fact matters enough to keep, it goes in
the reply, not the ticket.

Use these exact phrases, so every ticket reads the same way.

1. `I had AI (<model>, <effort> effort) analyze this test-affecting bug and develop a fix. Hope it helps!`
   `test-affecting` is not a judgement call. Write it only when the ticket carries the
   `affects-tests` label, which the `labels` field in step 1 already gave you. No label,
   no `test-affecting`, so the line reads
   `I had AI (<model>, <effort> effort) analyze this bug and develop a fix. Hope it helps!`.
   When we ran into the bug in our own testing, the line reads instead
   `I ran into this bug during testing and had AI (<model>, <effort> effort) develop a fix for it. Hope it helps!`.
   Drop the line altogether when the comment answers a developer's own proposal, and
   start at the developer's name instead.
   A follow-up comment takes one line at the top instead, covering the whole comment:
   `All of the below comes from a further round on both points.` Word the tail for the
   real case - `on both points`, `on your proposal`, `on the review comments`.
2. `{noformat}` with an ASCII diagram of the root cause: the broken statement or option on
   top, the order of events under it, the wrong end state at the bottom.
3. `The proposed fix:` then `{noformat}` with one line per file, saying what it does.
4. `{code:cpp}` with the whole `fix.diff`.
5. `The patch is formatted for <branch>.` Just the branch. No head sha, no `as of today`.
6. `Testing:` then one sentence, two at most. The suite name and its pass count with the
   fix in, and that the code the patch changes is the same in the branches this upmerges
   to. Nothing else.
   Never describe how the testcase detects the bug. No `it fails on a stock build and
   passes with the fix`, no `which succeeds where the test expects a refusal`, no line
   naming the reverse gate, the gate proofs, the `--ps-protocol` run or the
   identical-tree diffs. The developer reads the test and sees that for themselves, so
   spelling it out announces rigour rather than showing it. Baseline-versus-patched
   counts belong in the reply to the user, not on the ticket.
7. `Test:` then `{code:sql}` with the MTR `.test`. No `.result`.
8. The closing line depends on who you address. Check the handle is an active account
    before you use it. A ticket's assignee is often someone who has left, and a mention
    of a disabled account reaches nobody.

    ```
    PAT=${JIRA_PAT:-$(cat ~/.config/mariadb-qa/jira.pat)}
    curl -s -H "Authorization: Bearer $PAT" \
      "https://jira.mariadb.org/rest/api/2/user?username=<handle>" | grep -o '"active":[a-z]*'
    ```

    On `"active":false`, address the developer who wrote the code in this area instead,
    and say so in one line.

    To a manager, as listed in `~/mariadb-qa/skills/_shared/default_assignees.md`:
    `[~<name>] Would you assign this for review and final patch work please?`
    To anyone else, so to a developer:
    `[~<name>] Would you please review & finalize the patch?` Never write `push`.
    Add `It would help our testing as we regularly run into this.` only on the first
    patch posted to a ticket that carries the `affects-tests` label, which the `labels`
    field in step 1 already gave you. No label, no line. A later patch on the same
    ticket does not carry it either, whatever the label says.
    A design call stays with the developer. Where the work turns up a choice about how
    the server should behave, report what each way costs and hand the decision back in a
    few words: `On the reporting mismatch, I will leave that with you.` Never put it as a
    colleague-level question (`which way would you like this handled?`), never as a menu
    (`option A or option B?`), and never in wording that reads as though your approval
    matters (`splitting it out is fine if you prefer`).
9. When the comment answers a developer's own proposal, that opener is the whole first
    line of the comment: `[~<name>], I evaluated your proposal.` Point 1's line
    does not go above it. Report what it costs; do not explain their subsystem back to
    them. A follow-up opens with the point itself, `<Name>, on your proposal.`

Say that the work came from AI only with reason, as the opening line of point 1 and the
first line of the short form do. The bracket names the model that developed the fix and
its effort level, such as `(Opus 5.5, max effort)`: the model the session runs on, and the
effort level in `$CLAUDE_CODE_EFFORT_LEVEL`. No `(AI Generated)` tag and no side-note in
the body. A follow-up comment and a reply to a developer's proposal carry no AI mention
at all.

Never hedge the work either. No `this may not be correct`, no `a developer should
verify`, no `not senior-dev proven`. State what was run and what came out, and stop
there. Where something genuinely was not checked, name it in one plain sentence - `the
Enterprise builds were not run` - rather than wrapping the whole comment in a caveat.
That covers a run that was skipped, never a part of the fix. Every diff in the comment is
built and has passed the four gates, so a second, untested diff for another branch stays out.

Two more things never go in a comment, because each one talks about our own process
rather than about the server:

- **A not-exposed or configuration-gate caveat.** No `a server where the install script
  was never run is not exposed`, no `only reachable when the plugin is loaded`. The
  developer knows their own subsystem's setup.
- **A note on what the testcase proves.** Covered above under point 6.

Where the work turns up a second defect, write `That is a separate issue.` Never
`a separate report`, never `a separate finding`, never `filed separately` - those name
our paperwork, and the reader only cares that the fix in front of them does not cover
it. Then go and file that issue, in the same run. A second defect named in a comment
and left unfiled is a defect nobody can act on.

Never paste CLI output, MTR output or an error-log line in a bare `{noformat}` block.
Every such block carries the version banner of the build it came from:
`{noformat:title=<CS/ES> <version> <full sha> (<build type>, <compiler>) Build <DD/MM/YYYY>}`.
That is the line `~/stack`, `~/b` and `~/tt` already emit, so take it from the tool
output. For a run the tools did not produce, read the banner in that basedir with
`source ~/mariadb-qa/version_chk_helper.source` and build the title from
`${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE} ${BUILD_DATE}`. A renamed
basedir breaks that parse, so check the title before the block goes in. Without the
banner the reader cannot tell which build produced the output.

Never label evidence with the word "measured" in any form - no `Measured:`, no
`As measured:`, no `Measured on 13.1:`. End the sentence before the block with a
colon and let the numbers speak. Announcing rigour is not the same as showing it.

Attach nothing. The diff and the test sit in the comment body, so the reader
has all of it without a download.

Worked example: MDEV-36356 comment 337905.

### 9. Link the neighbours

Search the ticket's own links and the known-bug list for tickets in the same family, and
add a `Relates` link for each one whose testcase has the shape your fix covers. A closed
duplicate whose testcase still crashes is worth linking, because that fact is news. Skip a
ticket that only shares a generic four-frame stack.

```
~/jira --link <KEY> --relates <OTHER> --link-type Relates --dry-run
```

Set the version fields from the code read, not from a test run. If the code the bug sits
in is the same in a branch, that branch is affected. Fix Version stops below the version main
builds (read `VERSION` on main), so when main builds 13.3, 13.2 is the highest.
`~/jira --edit <KEY> --affects-version 13.3 --fix-version 13.2` is additive. Only run a version check when the code read leaves it unclear. The
link and the version fields need the same approval as the comment, so propose them and wait.

Never run a version matrix just to fill these fields, it costs far more than it returns.
When a matrix is genuinely wanted, drive it from `./gendirs.sh` (or `./gendirs.sh san`,
`tsan`, `msan`, `val`) through `mtr_testrun.sh`, never a hand-rolled list of basedirs, and
prove the testcase actually detects the bug first. For a test that lives in a suite rather
than `main`, use `~/mariadb-qa/claude/claude_mtr_matrix.sh <test> <suite>` instead:
`mtr_testrun.sh` calls `./mtr <bare test name>`, which never selects a suite test, so every
row reads clean. A test that passes on a broken build
reports every version as clean.

Check first whether the `eb` file already exists and is tracked. When it does, add only
what is missing. Do not restyle what is there, even when the house style differs from
yours: each block repeats its own setup on purpose, so that it replays on its own.

Register each new UniqueID the baseline produced with `kb`, or `kba` for a sanitizer one,
and put the testcases in `eb <number>`. Use the UniqueIDs the real instance printed, never
a handcrafted one. A bug with no crash has no UniqueID, so only `eb` applies.

Every shape you found goes in, not only the ones the ticket listed. That is the whole
point of the probe round, and a shape left out is a shape nobody can replay.

An `eb` file holds SQL only. Add each new testcase as bare SQL, one blank line between
blocks. Each block is self-contained: it carries its own setup, so it replays on its own
in a fresh instance. Repeat the setup in every block, even when the block above already
has it. Write no remark above a testcase to say what it shows. Two exceptions.

An error or CLI bug records its output below the testcase, one line each, no timestamp.
`#ERR: - (no error)` says the error log stayed quiet.

```
#CLI: ERROR 1038 (HY001): Out of sort memory, consider increasing server sort buffer size
#ERR: [ERROR] mariadbd: Out of sort memory, consider increasing server sort buffer size
```

A testcase that needs server options carries one line directly above it. Automation reads
that line, so copy the format exactly, the two spaces after the colon included.

```
# mysqld options required for replay:  --log_bin
```

`BUGS/MDEV-39544.sql` and `BUGS/MDEV-25045.sql` show both forms.

Before you write the reply, answer these two out loud:
- Which shapes did I find, and is each one now in `eb <number>`?
- Which UniqueIDs did the baseline print, and is each one now in `kb` or `kba`, or already
  there under this ticket?

Say what you added and what was already present. Both files are tracked, so list them for
`git add` at the end.

## Self-checks

- Read the diff back and remove any hunk outside the fix.
- Check that the code the patch changes is the same in the branches this upmerges to, and
  that anything the fix leans on exists there. Say it in those words, not "anchors".
- Whenever a check turns up a bug, run another full review of the change and another bug
  hunt. Loop until clear.
- Report per testcase what you observed. "Tests pass" only when nothing was skipped.
- No clickable question anywhere in the reply, and nothing at all after the four-gate block.
- Is anything in the reply work you could have done instead of asking? Do it, then reply.
- Re-run the step 4 call-site sweep against the final diff. Every site it lists is either
  fixed here or carries a one-line reason it needs nothing.
- Read the diff for anything on the step 3c list. Each one goes, unless it is an assert that
  checks removed code, or one you proved wrong.
- The fix follows the direction the developers gave, or the reply carries the testcase that
  shows why it cannot.
