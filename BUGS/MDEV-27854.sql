CREATE TABLE t2 (c INT,c2 CHAR(1),c3 DATE) ENGINE=InnoDB;
CREATE PROCEDURE p (cnt INT(1)) SELECT COUNT(*) INTO cnt FROM t;
CREATE VIEW t AS SELECT * FROM t2;
CREATE TEMPORARY TABLE t (c TEXT);
CALL p (1);
DROP TEMPORARY TABLE IF EXISTS t,t2;
CALL p (1);