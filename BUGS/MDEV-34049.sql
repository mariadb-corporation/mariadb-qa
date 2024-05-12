# Very sporadic
# MYEXTRA="--no-defaults --sql_mode="
# MASTER_EXTRA="--log_bin=binlog --binlog_format=STATEMENT --log_bin_trust_function_creators=1 --server_id=1"
# SLAVE_EXTRA="--slave-parallel-threads=11 --slave-parallel-mode=aggressive --slave-parallel-max-queued=1073741827 --slave_run_triggers_for_rbr=LOGGING --slave_skip_errors=ALL --server_id=2"
CREATE TABLE t1 (a1 VARCHAR(1), a2 VARCHAR(1)) ENGINE=InnoDB;
XA START 'a';
CREATE TEMPORARY TABLE t1 (c1 INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES ('a');
INSERT IGNORE INTO t1 VALUES (@inserted_value);
XA END 'a';
XA ROLLBACK 'a';
SET SESSION gtid_domain_id=102;
