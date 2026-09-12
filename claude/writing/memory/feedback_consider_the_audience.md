---
name: feedback_consider_the_audience
description: Work out who reads the text before writing a word of it. Strip internal detail from anything that leaves the team, and never assume a pronoun.
metadata:
  type: feedback
---

Before writing anything, work out who reads it. The reader decides the register, the detail level and what may appear at all.

**Strip what does not belong outside.** Text going to a public tracker, a customer or anyone outside the team carries no internal instructions, no private rules, no team vocabulary, no internal identifiers and no internal paths. A developer cannot look up a job number or a local path, so name the evidence by what it is: "one core", "the second run", "in one case". Tell two cases apart by the observation, not by a number.

**Facts only in a ticket comment.** A ticket comment can be read by the customer. It carries what was run, what came out, what the code does and what the operator sees, and nothing else. No impact statement of any kind, and nothing that reads as criticism even when it is true: not what a defect, a message or a wait cost anyone, not a verdict on a product, another team's work or anyone's handling of the case. An internal judgment belongs in a dev-only comment or off the ticket.

**Never assume a pronoun.** Write "the user", "the developer", "the assignee", or the role. A name does not tell you someone's pronouns. Where a pronoun is unavoidable and none is known, use they/them.

**Match the level.** A developer reading about their own subsystem needs the result, not an explanation of their code. A tester reading a summary needs plain words, not function names.

**Why:** text written without a reader in mind carries internal material outward and reads wrong to whoever gets it.

**How to apply:** name the reader first, then write. Re-read once as that reader before handing over.

Related: [[feedback_write_to_the_reader]], [[feedback_plain_language]], [[feedback_report_dont_direct]].
