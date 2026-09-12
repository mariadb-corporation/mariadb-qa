# Setup procedure

This file is for Claude Code. It installs the writing setup on this machine and builds the user's voice profile. Read this whole file and README.md before acting. Work in the main conversation and do not start a subagent. Do not post anything to Jira, Slack or email at any step. Do not change files outside ~/.claude, apart from the corpus file the user names. The kit directory is the directory this file is in.

## 1. Intake

Ask these questions in one message and wait for the answers. Do not install before they arrive.

1. Role: tester, developer, support or other. This picks the role section of the rules.
2. Channels: which of Jira, Slack, email, reports, commit messages and code review are written with Claude's help.
3. Audience: who reads most of it. Developers on the team, other teams, customers, or a mix.
4. AI line: should text that carries a fix, a patch, a testcase or an analysis say in passing that AI helped? Yes or no. README.md explains the line under Working with it.
5. Past writing: is there a file of the user's own comments, or should the export from Jira run? For the export, a Jira Personal Access Token must sit in JIRA_PAT or in ~/.config/mariadb-qa/jira.pat.
6. How to refer to the user in the voice profile: first name, handle, or "the user".
7. Anything Claude must never do in text sent as the user.

The role and the AI line are the two install switches. The other answers shape the profile only.

## 2. Install the files

Run from the kit directory:

    ./install.sh --role <role>

Add --no-ai-line when the answer to question 4 was no. Show the user the script's output as printed. The script installs the rules, the seed memories and the output style, adds one import line to ~/.claude/CLAUDE.md, and sets the output style in ~/.claude/settings.json when none is set. It never overwrites a file the user already has. When it reports that a file differs and was kept, tell the user and leave it. They decide on --force.

## 3. Collect the corpus

Target 100 to 200 of the user's own comments. Fewer than 50 gives a generic profile. Say so, and offer to add other prose of theirs (emails, Slack messages, commit messages) to the file by hand.

The export from Jira:

    python3 ./export_my_comments.py --out ~/.claude/writing/corpus.txt --holdout ~/.claude/writing/corpus_holdout.txt --max 200

The first file holds the user's own comments, newest first, with code and log blocks removed. The second holds four comments set aside for the self-test in step 6. Do not read the second file before step 6. It may include comments with restricted visibility. It stays on this machine and is deleted at the end of step 6 unless the user wants to keep it.

Or take the file the user named. Before reading it, cut four comments spread over the file into ~/.claude/writing/corpus_holdout.txt. Then read all of the rest, in full. Do not sample.

## 4. Distil the voice profile, in two rounds

Read voice-profile/SKILL.template.md in the kit directory. Write ~/.claude/skills/voice-profile/SKILL.md from it, in two rounds.

The export is newest first, so the halves are periods: round one covers the recent habits and round two the older ones.

Round one: read the first half of the corpus and write the whole profile from it.

Round two: read the second half against the profile. For each section, confirm, correct or add. Adjust the frequencies. Add the words and shapes that appear in neither half to the anti-patterns. Replace a quoted example when the second half holds a clearer one. A profile built from one pass keeps the habits of one period and misses the rest.

Rules for both rounds:

- Fill every section from the corpus. Quote real phrases verbatim and short. Mark frequency where it helps: "in about a third of comments". Do not invent a phrase the corpus does not show.
- Replace every other person's handle in a quote with [~assignee]. No names of other people anywhere in the profile, bare first names in quoted prose included: replace the name with the role, or drop the quote.
- Refer to the user the way they chose in intake.
- Look for, in this order: how they open; how they agree, acknowledge and admit an error; how they disagree; how they ask; how they close; connectives and abbreviations; hedges; sentence length and punctuation; spelling variant; words they always use and words that never appear; how they lay out evidence; how they answer a numbered message; how they thank; how they hand off.
- Anti-patterns: keep the generic paragraph, then add the markers specific to this user, each with the plain form they write instead.
- Improvement latitude: list the recurring typos seen in the corpus. State what a rewrite must never remove.
- Worked example: one real comment not quoted elsewhere in the profile, with a generic AI draft of the same content above it.
- Remove every line that starts with "> fill:" and every "<...>" placeholder. Check with the command below and read its hits: a placeholder is wrong, a less-than sign in prose is fine.

      grep -n '> fill:\|<[a-zA-Z]' ~/.claude/skills/voice-profile/SKILL.md

- Write the profile itself in plain English: simple sentences, common words. Keep the file under about 250 lines. Claude Code asks the user for approval before a write under ~/.claude; the user approves the profile write once. The hyphen, never the em-dash. The frontmatter description stays under 1,500 characters and names the corpus size.

## 5. Review with the user

Tell the user the profile is written and give its absolute path. Show in chat the Role understanding section and the user-specific anti-patterns only. They read the rest in the file. Ask for corrections and apply each one to the profile.

A correction that is a rule rather than voice ("never put a version on every line") also becomes a memory: one file in ~/.claude/writing/memory/ in the shape the seed files use, with a Why line and a How to apply line, and one index line in MEMORY.md there.

## 6. Self-test

Take two of the four held-out comments. For each, write two lines that state the situation in your own words, facts only, with no wording from the original: the ticket in a few words, and what the comment had to say. Draft a comment from those two lines in the user's voice, with the profile and the rules. Show the draft and then the original. Ask the user for a rating from 0 to 5 for each draft, and what the gap is. The drafts carry no evidence blocks, because the export strips them, so the rating covers voice and shape. The AI line does not apply here: the content is the user's own.

Save what each gap teaches. A voice point goes into the profile. A rule goes into a memory. Repeat once with the other two held-out comments when a rating is under 4.

Delete the corpus file and the held-out file when the user does not want to keep them.

## 7. Finish

Tell the user:

- The changes to CLAUDE.md, the output style and the settings load at the next session. Restart Claude Code and run /context. ~/.claude/CLAUDE.md is listed under Memory files, and the rules and the memory index load through its import line. Asking Claude for the first heading of its writing rules confirms it.
- The voice profile loads on its own when a task matches its description, and by name with /voice-profile.
- How to correct from now on: say what was wrong and what was wanted, and ask for it to be saved. Each correction becomes a memory. A rating from 0 to 5 after a deliverable is welcome now and then.
- The installed paths, from the install output.

Report what was done and, if anything was skipped, what and why.
