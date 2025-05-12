SET unique_checks=0,foreign_key_checks=0;
CREATE TABLE t (c INT) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t VALUES (1);
XA END 'a';
XA PREPARE 'a';
SHUTDOWN;
