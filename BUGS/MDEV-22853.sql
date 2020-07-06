USE test;
CREATE TABLE t(a INT) PARTITION BY KEY (a);
CREATE TRIGGER tr AFTER UPDATE ON t FOR EACH ROW DROP SERVER IF EXISTS s;
INSERT INTO t VALUES(0);
UPDATE t SET a = 1;