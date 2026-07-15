---
name: email
description: Send a plain-text email from this box via direct-to-MX SMTP (no local MTA, no credentials). Resolves the recipient domain's MX and delivers straight to the receiving mail server over STARTTLS, with a valid Message-ID and Date so Google/RFC-5322 filters accept it. Default sender is claude@<hostname>. Use when asked to email someone from this machine, send a test/notification message, or mail a short report. Not for inbox-grade authenticated mail (use the Superhuman Mail MCP tool for that).
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# email

Sends a plain-text email straight to the recipient domain's MX server over STARTTLS. No local mail client, MTA, or SMTP credentials are involved - the box talks SMTP directly to the receiving server.

The helper `send_email.py` resolves MX via `dig +short MX <domain>` (lowest priority first, with implicit-MX fallback to the A record), sets a valid `Message-ID` and `Date` (Google rejects mail without them: `550 5.7.1 ... RfcMessageNonCompliant`), and tries each MX until one accepts.

## Inputs

- `--to` - recipient address (required).
- `--subject` - subject line (required).
- `--body` - body text, or `--body-file <path>` (`-` for stdin). Empty if omitted.
- `--from` - sender address. Default `claude@<hostname>`.
- `--html-file <path>` - optional HTML alternative body (`-` for stdin). Produces a multipart text+HTML message so clients render bold/links; `--body`/`--body-file` is then the plaintext fallback.

If the user gives only a recipient and a message, infer subject and body from context; ask only when genuinely ambiguous.

## Run

```bash
python3 ~/.claude/skills/email/send_email.py \
  --to you@example.com \
  --subject "Subject here" \
  --body "Message body here"
```

Body from a file or heredoc:

```bash
python3 ~/.claude/skills/email/send_email.py --to you@example.com \
  --subject "Report" --body-file /tmp/report.txt
```

Success prints `ACCEPTED via <mx> ... refused {}`. Report that line back.

## Caveats

- `ACCEPTED` means the receiving MX took the message into its pipeline, NOT that it reached the inbox. Mail from `claude@<hostname>` has no SPF/DKIM/DMARC for the sending IP, so it can be filtered to Spam/Quarantine. Tell the user to check spam if unseen.
- For reliable inbox-grade mail sent as the user's real address, use the Superhuman Mail MCP tool (authenticate via `/mcp`) instead.
- Sending email is outward-facing: confirm recipient, subject, and body with the user before sending unless they have already authorized this specific send.
