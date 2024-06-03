CREATE TABLE t (a INT) ENGINE=InnoDB;
INSERT INTO t (a) VALUES (0);
XA BEGIN 'a';
SELECT * FROM mysql.innodb_index_stats LOCK IN SHARE MODE;
INSERT INTO t (a) VALUES (0);

SET GLOBAL innodb_stats_persistent=0;
CREATE TABLE t (c INT) ENGINE=InnoDB;
XA START 'a';
UPDATE mysql.innodb_index_stats SET stat_value=0;
SET GLOBAL innodb_stats_persistent=DEFAULT;
SELECT * FROM t;
SET GLOBAL table_open_cache=DEFAULT;
INSERT INTO t VALUES (0,0,0,0,0,0);
# Also shows: [ERROR] InnoDB: Cannot save index statistics
