# Requires standard m/s setup, slave will crash
CREATE VIEW c AS SELECT 1 c;
CALL sys.statement_performance_analyzer (1,1,1);
DROP VIEW c;
SET sql_log_bin=1;
CREATE TABLE c (a INT);
