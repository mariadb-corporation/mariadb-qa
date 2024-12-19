# mysqld options required for replay: --innodb-rollback-on-timeout=1
SET SESSION pseudo_slave_mode=ON;
CREATE TABLE t (a INT) ENGINE=INNODB;
XA START 'a';
INSERT INTO t VALUES (1);
XA END 'a';
XA PREPARE 'a';
ALTER TABLE t IMPORT TABLESPACE;
