CREATE TABLE t2 (c1 VARCHAR(1) KEY,INDEX idx1 (c1)) ENGINE=InnoDB;
INSERT INTO t2 VALUES ('x'),('1'),('a'),('b');
SET optimizer_trace='enabled=on';
SELECT 1 FROM t2 WHERE NOT c1<RAND() GROUP BY c1 LIMIT 3;
