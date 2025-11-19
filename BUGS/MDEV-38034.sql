SET SQL_MODE='';
CREATE TABLE t1 (a INT) ENGINE=INNODB;
CREATE TABLE t2 (a INT) ENGINE=INNODB;
SET transaction_isolation='SERIALIZABLE';
SET transaction_read_only=1;
HANDLER t2 OPEN;
SET transaction_read_only=0;
INSERT INTO t1 VALUES ('a');

CREATE TABLE t (c1 INT) ENGINE=INNODB;
SET transaction_read_only=1;
SET transaction_isolation='SERIALIZABLE';
HANDLER t OPEN;
SET transaction_read_only=0;
ALTER TABLE t DISCARD TABLESPACE;
