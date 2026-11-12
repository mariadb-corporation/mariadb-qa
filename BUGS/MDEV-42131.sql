# Requires MTR: after the CREATE TRIGGER, change the sql_path line of v1.frm to sql_path=`x and of t1.TRG to sql_path='`x', then run the rest; ref bug report for MTR testcase
CREATE VIEW v1 AS SELECT 1 AS a;
CREATE TABLE t1 (a INT);
CREATE TRIGGER tr1 BEFORE INSERT ON t1 FOR EACH ROW SET NEW.a= NEW.a + 1;
FLUSH TABLES;
SELECT * FROM v1;
INSERT INTO t1 VALUES (1);
