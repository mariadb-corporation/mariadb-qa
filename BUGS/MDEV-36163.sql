CREATE TABLE t (a INT,v VECTOR (1) NOT NULL,VECTOR INDEX (v)) ENGINE=INNODB;
LOCK TABLE t WRITE;
INSERT INTO t VALUES (1,0x30303030);
INSERT INTO t VALUES (1,0x31313131);
