# Writing setup for Claude Code

A setup that makes Claude Code write clear, short, plain English for other people, in your own voice: Jira comments and descriptions, Slack messages, email, reports, commit messages, and its replies to you.

It has three layers.

1. Writing rules. What goes in, what stays out, and how text is delivered: plain English, lead with the answer, ASCII punctuation, timeless prose, facts only in a ticket, report and suggest rather than direct, Jira wiki markup from the first line. Installed as one file that your user-level CLAUDE.md imports, plus a short output style for chat replies.
2. Your voice. A skill that Claude builds from 100 to 200 of your own comments, in two rounds: how you open, agree, ask and close, which words you use and never use, and a worked example. Text sent as you then reads as you, not as an assistant.
3. Corrections that stick. A memory directory, seeded with the corrections that recur most, and a standing rule that every correction you give becomes one more memory file. Claude reads the memories that apply before it writes.

Plain English, PE for short, runs through all three layers: simple sentences, common words, one idea per sentence, no dead prose. The first two layers remove most of the machine-written markers on day one. The third is where the result comes from over time. Re-reading what Claude writes before it goes out stays part of the job. The corrections get cheaper, because each one is made once.

## Requirements

- Claude Code, a recent version. The setup uses imports in ~/.claude/CLAUDE.md, ~/.claude/output-styles and ~/.claude/skills.
- curl or wget, and python3. Nothing else.
- A Jira Personal Access Token (PAT) for the export, in the JIRA_PAT environment variable or in ~/.config/mariadb-qa/jira.pat (mode 600). Create one under your Jira profile, Personal Access Tokens. Without a token, put 100 to 200 of your own comments in a text file by hand and name that file when asked.

## Install

No clone is needed. One command fetches the kit files into ~/.claude/writing-kit:

    curl -fsSL https://raw.githubusercontent.com/mariadb-corporation/mariadb-qa/master/claude/writing/get.sh -o /tmp/get_writing_kit.sh && bash /tmp/get_writing_kit.sh

It makes one call to the GitHub API for the file list and downloads each file by its raw URL. Then start Claude Code in your home directory and paste:

    Read ~/.claude/writing-kit/SETUP.md and follow it.

With this repository already on the machine, skip the fetch and name this directory instead.

Claude asks a few questions, runs the install script, exports your comments, writes your voice profile, reviews it with you and runs a short self-test. Claude Code asks before it writes under ~/.claude; approve the voice profile write when asked. Plan on about an hour. Restart Claude Code once at the end so the new files load. /context then lists ~/.claude/CLAUDE.md under Memory files, and the rules and the memory index load through its import line.

The install script also runs on its own:

    ./install.sh --role tester|developer|support|other [--no-ai-line] [--force] [--home DIR]

--home DIR installs under another directory, for a test run.

## What is installed where

| Path | What it is |
|---|---|
| ~/.claude/CLAUDE.md | Gains one line, an import of the rules file. Nothing else changes. |
| ~/.claude/writing/rules.md | The writing rules: the common part, your role's part, and the AI line rule unless declined. |
| ~/.claude/writing/memory/ | The memory files and MEMORY.md, their index. Corrections land here. |
| ~/.claude/output-styles/brief.md | The chat output style: lead with the answer, no preamble, no recap. |
| ~/.claude/settings.json | outputStyle set to brief, only when no style was set. |
| ~/.claude/skills/voice-profile/SKILL.md | Your voice profile, written from your comments. |

The output style sets keep-coding-instructions, so the built-in software engineering behavior of Claude Code stays in place.

## Working with it

Claude uses the voice profile on its own for text written as you, and by name with /voice-profile. Ask for "PE" and Claude rewrites a text in plain English under the rules. Jira text comes out in wiki markup. A paste-ready text longer than a few paragraphs arrives as a file with its path, because the chat corrupts a long paste.

To correct something, say what was wrong and what you wanted, and ask Claude to save it. It writes one memory file and one index line. To confirm something that went right, say so. That is saved the same way. A rating from 0 to 5 after a deliverable, now and then, gives Claude a measure to work against.

The AI line: when a text carries a fix, a patch, a testcase or an analysis that AI produced, the rules have Claude say so in passing, once per comment and at the top, as in "I evaluated your proposal with AI." or "a further AI round found". The reader can then weigh work that is good but not senior-reviewed. A plain test result or a cross-reference gets no line. The line is on by default. Install with --no-ai-line to leave it out.

The rules tell Claude never to post to Jira, Slack or email on its own: it drafts, shows, and waits for your approval of the exact text. Rules are instructions, not enforcement, so the read before posting stays yours.

## Keeping it current

Re-run the fetch command, then install.sh, to pick up a newer kit. install.sh adds new seed memories and never overwrites a file you have, including memories you edited. To replace the rules file or the output style with the repository version, add --force. The previous file is kept beside it with a .bak suffix.

Edit any installed file directly. They are plain markdown. Keep MEMORY.md to one line per memory.

## Removing it

Delete the import line from ~/.claude/CLAUDE.md, then remove ~/.claude/writing, ~/.claude/writing-kit, ~/.claude/output-styles/brief.md, ~/.claude/skills/voice-profile and the outputStyle entry in ~/.claude/settings.json.

## Files in this directory

| File | Purpose |
|---|---|
| get.sh | Fetches the kit from GitHub into ~/.claude/writing-kit, no clone needed. |
| SETUP.md | The procedure Claude follows: intake, install, corpus, profile, review, self-test. |
| install.sh | Copies the files into place. Safe to re-run. |
| export_my_comments.py | Writes your own Jira comments to a text file, newest first, code blocks removed. |
| rules/ | The writing rules: common.md, role-tester.md, role-developer.md, role-support.md, ai-line.md. |
| output-styles/brief.md | The chat output style. |
| memory/ | The seed memories and their index. |
| voice-profile/SKILL.template.md | The skeleton of the voice profile, filled from your comments. |
