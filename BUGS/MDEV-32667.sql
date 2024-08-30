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
# ERR: [ERROR] InnoDB: Cannot save index statistics for table `test`.`t`, index `GEN_CLUST_INDEX`, stat name "n_diff_pfx01": Lock wait timeout

CREATE TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES (0),(0);
INSERT INTO t VALUES (0),(0);
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
XA START 'a', 'b';
INSERT INTO t VALUES (0),(0);
SELECT * FROM mysql.innodb_index_stats WHERE table_name='t';
SELECT SLEEP(10);
# ERR: [ERROR] InnoDB: Cannot save index statistics for table `test`.`t`, index `GEN_CLUST_INDEX`, stat name "n_diff_pfx01": Lock wait timeout

CREATE TABLE t (c1 INT,c2 INT,c3 INT);
INSERT INTO t VALUES (0,0,0),(0,0,0),(0,0,0);
INSERT INTO t VALUES (0,0,0),(0,0,0),(0,0,0);
XA START 'a';
SELECT SLEEP(5);
DELETE FROM mysql.innodb_table_stats;
SELECT SLEEP(7);
# ERR: [ERROR] InnoDB: Cannot save table statistics for table `test`.`t`: Lock wait timeout
