CREATE TABLE t (a INT) ENGINE=INNODB;
INSERT INTO t SELECT * FROM seq_1_to_1000;
ALTER TABLE t ADD hid INT DEFAULT 2;
INSERT INTO t VALUES (1,1);
ALTER TABLE t DISCARD TABLESPACE;
DROP TABLE t;
CREATE TABLE t (a CHAR KEY,b CHAR,KEY(b)) ENGINE=INNODB;
CHECK TABLE t;