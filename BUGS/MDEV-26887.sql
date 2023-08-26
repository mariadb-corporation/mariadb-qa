# mysqld options required for replay:  --gtid_strict_mode=1 --log_bin=binlog --binlog_format=ROW --log_bin_trust_function_creators=1 --server_id=1
# mysqld options required for replay (slave):  --relay-log=relaylog --slave-parallel-threads=65 --slave-parallel-mode=aggressive --slave-parallel-max-queued=1073741827 --slave_run_triggers_for_rbr=LOGGING --slave_skip_errors=ALL --server_id=2
SET SESSION binlog_format=MIXED;
CREATE TEMPORARY TABLE t1(c INT) ENGINE=Aria;
DROP TABLE t1;
CREATE TEMPORARY TABLE t2(c INT) ENGINE=INNODB;
LOAD DATA LOCAL INFILE 'nosuchfile.txt' INTO TABLE t1;
CREATE TEMPORARY TABLE t1 AS SELECT 1;
CREATE TABLE t1 (c INT);
RENAME TABLE t1 TO t5;
INSERT INTO t1 VALUES (1);
# Slave crashes
