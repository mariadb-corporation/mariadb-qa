#!/usr/bin/env python3
# Created by Roel Van de Paar, MariaDB
"""Send a plain-text email from this box via direct-to-MX SMTP + STARTTLS.

Resolves the recipient domain's MX records (lowest priority first, implicit-MX
fallback to the A record) and delivers straight to the receiving mail server.
No local MTA or credentials are used.
"""
import argparse
import smtplib
import socket
import ssl
import subprocess
import sys
from email.message import EmailMessage
from email.utils import formatdate, make_msgid


def mx_hosts(domain):
  """Return MX hosts for domain, lowest priority first; implicit-MX fallback."""
  try:
    out = subprocess.run(
      ["dig", "+short", "MX", domain],
      capture_output=True, text=True, timeout=15,
    ).stdout.strip()
  except Exception:
    out = ""
  hosts = []
  for line in out.splitlines():
    parts = line.split()
    if len(parts) == 2 and parts[0].isdigit():
      hosts.append((int(parts[0]), parts[1].rstrip(".")))
  if hosts:
    return [h for _, h in sorted(hosts)]
  return [domain]


def main():
  ap = argparse.ArgumentParser(description="Send mail via direct-to-MX SMTP.")
  ap.add_argument("--to", required=True, help="recipient address")
  ap.add_argument("--subject", required=True)
  g = ap.add_mutually_exclusive_group()
  g.add_argument("--body", help="message body text")
  g.add_argument("--body-file", help="read body from a file ('-' for stdin)")
  ap.add_argument("--from", dest="sender",
                  default="claude@%s" % socket.gethostname(),
                  help="sender address (default claude@<hostname>)")
  ap.add_argument("--html-file", dest="html_file",
                  help="optional HTML alternative body from a file ('-' for stdin)")
  args = ap.parse_args()

  if args.body is not None:
    body = args.body
  elif args.body_file == "-":
    body = sys.stdin.read()
  elif args.body_file:
    with open(args.body_file) as f:
      body = f.read()
  else:
    body = ""

  html = None
  if args.html_file == "-":
    html = sys.stdin.read()
  elif args.html_file:
    with open(args.html_file) as f:
      html = f.read()

  domain = args.to.rsplit("@", 1)[-1]
  helo = socket.gethostname()

  msg = EmailMessage()
  msg["From"] = args.sender
  msg["To"] = args.to
  msg["Subject"] = args.subject
  msg["Date"] = formatdate(localtime=True)
  msg["Message-ID"] = make_msgid(domain=helo)
  msg.set_content(body)
  if html is not None:
    msg.add_alternative(html, subtype="html")

  last_err = None
  for host in mx_hosts(domain):
    try:
      s = smtplib.SMTP(host, 25, timeout=25)
      s.ehlo(helo)
      if s.has_extn("starttls"):
        s.starttls(context=ssl.create_default_context())
        s.ehlo(helo)
      refused = s.send_message(msg)
      s.quit()
      print("ACCEPTED via %s | from %s | to %s | refused %s"
            % (host, args.sender, args.to, refused or "{}"))
      return 0
    except Exception as e:
      last_err = "%s: %s" % (host, e)
      continue

  print("FAILED to deliver to %s -> %s" % (args.to, last_err), file=sys.stderr)
  return 1


if __name__ == "__main__":
  sys.exit(main())
