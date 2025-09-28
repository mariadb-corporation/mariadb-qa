# Lightly sporadic. Repeat testcase till a crash is observed
SET max_statement_time=0.000001;
SELECT JSON_SET ('[','$[0]',0);

SET @@max_statement_time=0.0001;
SELECT JSON_SET ('[','$[0]',0);

SET @@max_statement_time=0.00001;
EXECUTE s;
SELECT JSON_SET ('[','$[0]',0);
