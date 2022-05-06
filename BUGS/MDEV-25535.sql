SET autocommit=OFF;
SET GLOBAL log_output=4;
CREATE TABLE t2 (user_str TEXT);
SET GLOBAL general_log=on;
INSERT INTO t2 VALUES (4978+0.75);
SET GLOBAL wsrep_cluster_address='';
SET SESSION wsrep_trx_fragment_size=1;
INSERT INTO t2 VALUES (10);
SAVEPOINT event_logging_1;
CREATE TABLE IF NOT EXISTS t3 (id INT) ENGINE=InnoDB;

CREATE TABLE t1 AS SELECT 1 AS c1;
SET GLOBAL wsrep_ignore_apply_errors=0;
SET SESSION wsrep_trx_fragment_size=1;
SET SESSION wsrep_trx_fragment_unit='statements';
SET AUTOCOMMIT=0;
CREATE TABLE t1 (id INT);
SAVEPOINT SVP001;
