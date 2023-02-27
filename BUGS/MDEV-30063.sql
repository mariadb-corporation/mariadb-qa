SET SESSION unique_checks=0;
SET foreign_key_checks=0;
SET GLOBAL innodb_stats_persistent=0;
CREATE TABLE t1 (c1 MEDIUMINT);
XA START 'a';
INSERT INTO t1 VALUES (3);
SET GLOBAL innodb_stats_persistent=1;
SET GLOBAL table_open_cache=+ 1;
INSERT INTO t1 VALUES (NULL,'a');
