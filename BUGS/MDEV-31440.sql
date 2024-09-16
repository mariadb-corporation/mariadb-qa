# Loop till a crash is seen
SET @@max_statement_time=0.0001;
CREATE TABLE t (c1 DATETIME PRIMARY KEY,c2 VARCHAR(40)) ENGINE=InnoDB;
UPDATE t t INNER JOIN (SELECT c1, MAX(c2) AS max_c2 FROM t GROUP BY c1) t_max ON t.c1=t_max.c1 SET t.c2=t_max.max_c2;
UPDATE t t INNER JOIN (SELECT c1, MAX(c2) AS max_c2 FROM t GROUP BY c1) t_max ON t.c1=t_max.c1 SET t.c2=t_max.max_c2;
DROP TABLE t;
