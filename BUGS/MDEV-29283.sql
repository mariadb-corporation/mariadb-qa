CREATE TABLE t(c CHAR (1)KEY ) ENGINE=MYISAM;
INSERT INTO t VALUES(3);
UPDATE t SET c= 1 ORDER BY(SELECT c LIMIT 0);