CREATE TABLE t (c1 VARCHAR(10),c2 VARCHAR(10),PRIMARY KEY(c1,c2),FULLTEXT KEY k (c2)) ENGINE=InnoDB;
INSERT INTO t VALUES ('a','b');

CREATE TABLE t (a INT,ROW_START TIMESTAMP(6) AS ROW START,ROW_END TIMESTAMP(6) AS ROW END,PERIOD FOR SYSTEM_TIME(ROW_START,ROW_END),INDEX (ROW_START),INDEX (ROW_END),PRIMARY KEY(ROW_END,a,ROW_START),INDEX (ROW_END,ROW_START,a)) WITH SYSTEM VERSIONING;
SHOW INDEX FROM t
