SET foreign_key_checks=0;
SET unique_checks=OFF;
SET autocommit=OFF;
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TRIGGER t2_ai AFTER INSERT ON t FOR EACH ROW SET @a:=(SELECT * FROM t);
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (1);
