SET SESSION transaction isolation level SERIALIZABLE;
CREATE TABLE t2 (c1 INT NOT NULL PRIMARY KEY);
XA START 'test';
SELECT * FROM mysql.innodb_index_stats WHERE table_name='t2' AND index_name='SECOND';
INSERT INTO t2 VALUES (1);
INSERT INTO t2 VALUES (2);
UPDATE mysql.innodb_table_stats SET last_update="2020-01-01" WHERE database_name="mysql" AND table_name="t2";

