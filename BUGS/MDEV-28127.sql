SET sql_mode='';
CREATE TABLE t1 (a INT,KEY(a)) ENGINE=InnoDB PARTITION BY RANGE (a) (PARTITION p VALUES LESS THAN (1));
CREATE TABLE t (a INT GENERATED ALWAYS AS (1) VIRTUAL,KEY(a));
ALTER TABLE t1 EXCHANGE PARTITION p WITH TABLE t;
INSERT INTO t VALUES (1);