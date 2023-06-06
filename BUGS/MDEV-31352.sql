SET autocommit=OFF;
SET GLOBAL wsrep_forced_binlog_format=0;
ALTER TABLE mysql.procs_priv ENGINE=InnoDB;
CREATE PROCEDURE p() INSERT INTO t VALUES (1);
DROP PROCEDURE IF EXISTS p;
