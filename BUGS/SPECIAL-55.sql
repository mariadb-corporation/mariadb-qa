CREATE TABLE t1 (c1 REAL(255,30),c2 DECIMAL,c3 VARCHAR(1) BINARY AS(c1) VIRTUAL,PRIMARY KEY(c1)) ENGINE=InnoDB TRANSACTIONAL=1;
INSTALL SONAME 'ha_connect.so';
CREATE TEMPORARY TABLE t2 (c1 INT KEY,c2 INT,c3 INT) ENGINE=InnoDB;
CREATE TABLE t2 (c1 INT,c2 VARCHAR(1)) ENGINE=CONNECT TABLE_TYPE=FIX FILE_NAME='/tmp/c_84.fix';
RENAME TABLE t2 TO t2_v;
CREATE TABLE t3 LIKE t1;
DELETE FROM a3,a1 USING t2 AS a1 LEFT JOIN t3 AS a2 ON a1.c1=a2.c1 LEFT   JOIN t3 AS a3 ON a2.c1=a3.c1;
# CLI: ERROR 1296 (HY000): Got error 174 'Open(r+b) error 2 on /tmp/c_84.fix: No such file or directory' from CONNECT
# ERR: OpenTable: Open(r+b) error 2 on /tmp/c_84.fix: No such file or directory
# ERR: [ERROR] Got error 174 when reading table './test/t2'
