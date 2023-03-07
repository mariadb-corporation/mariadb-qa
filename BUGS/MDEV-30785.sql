# Lightly sporadic. Repeat testcase till a crash is observed
SET max_statement_time=0.000001;
SELECT JSON_SET ('[','$[0]',0);
