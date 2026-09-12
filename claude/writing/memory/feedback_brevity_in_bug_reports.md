---
name: feedback_brevity_in_bug_reports
description: A bug report and a technical message use a short, neutral, factual register. The developers know their codebase, so no overstatement and no teaching of the obvious. The testcase and the raw output are the report.
metadata:
  type: feedback
---

Write in a short, neutral, factual register. Cut the narrative until only the facts that matter remain.

**A bug report holds:** a title that names the defect; a summary of one or two sentences; the testcase; the raw output, with the version of the build that produced it; the stack when it is relevant; the build setup; the version matrix; one short suggested fix when there is one; the introducing commit on one line.

**A bug report leaves out:** an "impact analysis" with several vectors; teaching prose; an executive summary that repeats the title; superlatives ("successfully demonstrated"); emoji check marks; more than one candidate patch; a list of threat models; how the finding was come by.

**Leave the standard behavior unstated.** The developers know how the test runner, the client, the tracker and the compiler behave. Keep out "no result file is needed because ...", "run this from the test directory", "compiled out under NDEBUG" and "an optimized build strips the assert". State the defect, show the code, and move on.

**Leave the reader's own subject unstated.** A developer knows what an error code means, what a clause does and how their own subsystem works. "Error 1140 describes a select list problem" reads as condescending. Report what you observed and stop there. A point inside their own area can be raised, but as a question rather than a recommendation.

**Length:** about 100 to 150 lines for a report on one defect. Under about 70 usually means the offending code or the fix is missing. Over about 200 usually means impact prose was added.

**Word choice:** the standard technical terms of the field are fine where they apply. Keep out slang, coined names and superlatives such as "CRITICAL" and "WIDESPREAD".

**Why:** the readers write the fixes. Long prose costs them time, and some of it reads as condescending. The calibration to aim for: another senior developer must see what you saw, and where.

**How to apply:** show the code, the run, the stack and a sketch of the fix. Cut the rest.

Related: [[feedback_write_to_the_reader]], [[feedback_bug_report_wording]], [[feedback_timeless_prose]].
