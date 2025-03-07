CREATE TABLE t (c INT,INDEX (c)) TRANSACTIONAL=1;
INSERT INTO t VALUES (1);
SELECT COLUMN_JSON(c) FROM t;
SHUTDOWN;

CREATE TABLE t (a INT,b INT) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0);
SELECT COLUMN_JSON(b) FROM t;
SHUTDOWN;

CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
INSERT INTO t VALUES (0,1,0);
SELECT COLUMN_JSON(c) FROM t;
SHUTDOWN;
# ERR (10.5): Warning: Memory not freed: 32  # On SELECT COLUMN_JSON(c) FROM t;
