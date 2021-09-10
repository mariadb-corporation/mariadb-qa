SET sql_mode='';
CREATE TABLE t0 (a TIMESTAMP) ENGINE=CSV;
INSERT INTO t0 VALUES (0);
RENAME TABLE t0 TO t;
SET sql_mode='traditional';
UPDATE t SET a=0;

# Then check error log for [ERROR] mysqld: Table 't' is marked as crashed and should be repaired
