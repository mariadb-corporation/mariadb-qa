SET SESSION max_session_mem_used=8192;
CREATE TABLE t1 (a INT, KEY(a)) ENGINE=InnoDB;
SET autocommit=OFF;
CREATE TABLE t2 (id INT NOT NULL PRIMARY KEY, DATA INT) ENGINE=MEMORY;
INSERT INTO t2(id) VALUES ('11');
ALTER TABLE t1 ADD COLUMN f3 INT NOT NULL DEFAULT 10;
LOCK TABLE t1 WRITE, t2 READ;
CREATE OR REPLACE TABLE t1 SELECT 1;