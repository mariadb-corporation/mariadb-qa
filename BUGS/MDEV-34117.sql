CREATE TABLE t1 (c INT);
CREATE TABLE t2 (c INT);
SET SESSION wsrep_trx_fragment_unit='STATEMENTS';
SET SESSION wsrep_trx_fragment_size=2;
DROP TABLE mysql.wsrep_streaming_log;
CREATE TRIGGER tgr AFTER INSERT ON t2 FOR EACH ROW UPDATE t1 SET c=c;
INSERT INTO t2 VALUES (1),(2);
