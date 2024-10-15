# Random order repeat the following SQL in 5000 threads (use --max_connections=10000):
CREATE TABLE t2 (c1 INTEGER);
CREATE TEMPORARY TABLE t1(c1 LONGTEXT NULL);
DROP TABLE t1;
DROP TABLE t2;
INSERT INTO t1  VALUES('a');
SET @@global.innodb_immediate_scrub_data_uncompressed=0;
SET @@global.innodb_immediate_scrub_data_uncompressed=1;
SET @@global.innodb_lru_scan_depth = 1536;
SET @@global.innodb_lru_scan_depth = 86400;
XA COMMIT 'a';
XA END 'a';
XA PREPARE 'a';
XA START 'a' RESUME;
XA START 'a';
