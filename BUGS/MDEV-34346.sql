# MASTER_EXTRA="--log_bin=binlog --binlog_format=STATEMENT"
# SLAVE_EXTRA="--slave-parallel-threads=10 --slave_skip_errors=ALL"
SET sql_mode='';
CREATE TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES (REPEAT (0,200000));
INSERT INTO t SELECT * FROM t;
INSERT INTO t VALUES (1);

# MASTER_EXTRA="--log_bin=binlog --binlog_format=STATEMENT --server_id=1"
# SLAVE_EXTRA="--slave-parallel-threads=10 --slave_skip_errors=ALL --server_id=2"
CREATE TABLE t ENGINE=InnoDB AS SELECT 1 c1;
INSERT INTO t VALUES (1);
DELETE FROM t WHERE c1=NULL;
INSERT INTO t VALUES(1) ON DUPLICATE KEY UPDATE c1=c1;
INSERT INTO t VALUES(1);
