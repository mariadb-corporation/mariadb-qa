CREATE OR REPLACE TABLE t1 (a INT) engine=InnoDB;
CREATE TABLE ti ( id BIGINT NOT NULL, PRIMARY KEY(id)) engine=InnoDB;
XA START 'a';
INSERT INTO t1 (a) VALUES (1);
SAVEPOINT s3;
XA END 'a';
XA PREPARE 'a';
SET GLOBAL wsrep_on=OFF;
XA ROLLBACK 'a';
SET GLOBAL wsrep_on=ON;
INSERT INTO ti VALUES (10);