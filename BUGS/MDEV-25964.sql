SET @@max_statement_time=0.0001;
CREATE TEMPORARY TABLE t (a INT PRIMARY KEY, b INT, KEY(b)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,1);
SELECT MAX(a)-MIN(a) FROM t GROUP BY b;
SELECT MAX(a)-MIN(a) FROM t GROUP BY b;
SELECT MAX(a)-MIN(a) FROM t GROUP BY b;
SELECT MAX(a)-MIN(a) FROM t GROUP BY b;  # Repeat as many times as needed to cause a crash
