USE test;
SET SQL_MODE='';
CREATE TABLE t (c1 INT UNSIGNED,c2 CHAR) PARTITION BY KEY (c1) PARTITIONS 2;
INSERT INTO t VALUES (NULL,0),(NULL,1);
ALTER TABLE t ADD PRIMARY KEY (c1,c2);
DELETE FROM t;

CREATE TABLE t1 (f CHAR(6)) WITH SYSTEM VERSIONING PARTITION BY system_time LIMIT 1 (PARTITION p1 HISTORY, PARTITION p2 HISTORY, PARTITION pn CURRENT);
INSERT INTO t1 VALUES (NULL);
UPDATE t1 SET f = 'foo';
UPDATE t1 SET f = 'bar';
CREATE VIEW v1 AS SELECT * FROM t1 FOR SYSTEM_TIME ALL;
UPDATE v1 SET f = '';
