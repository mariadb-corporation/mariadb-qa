USE test;
SET SQL_MODE='';
SET SESSION enforce_storage_engine=InnoDB;
CREATE TABLE t(f0 INT) ENGINE=InnoDB;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
XA START '0';
INSERT INTO t VALUES (0);
XA END '0';
XA PREPARE '0';
SET GLOBAL general_log=ON;

CREATE OR REPLACE TABLE mysql.general_log (c INT);
SET max_session_mem_used=32768;
XA START 'a';
XA END 'a';
SET GLOBAL general_log=ON;
XA PREPARE 'a';
SET GLOBAL general_log=ON;
