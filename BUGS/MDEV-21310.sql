CREATE TABLE t (c INT AUTO_INCREMENT KEY) ENGINE=InnoDB PARTITION BY LIST (c) (PARTITION p VALUES IN (1), PARTITION p2 VALUES IN (2));
ALTER TABLE t TRUNCATE PARTITION p;
INSERT INTO t PARTITION (p) (c) SELECT 1;