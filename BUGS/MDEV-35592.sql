CREATE TABLE t1 (id INT, b INT, u INT);
CREATE TABLE t2 (id INT, name VARCHAR(24));
CREATE TABLE t3 (id INT, name VARCHAR(24));
INSERT INTO t1 SELECT seq, NULL, 100000 + (seq - 1) DIV 4 FROM seq_1_to_3824;
INSERT INTO t1 VALUES (3825, NULL, NULL), (3826, NULL, NULL), (3827, NULL, NULL), (3828, NULL, NULL);
SET tmp_table_size= 16384, max_heap_table_size= 16384;
SELECT t1.id FROM t1 WHERE t1.u IN (SELECT t2.id FROM t2 WHERE t2.name LIKE 'x%') OR t1.b IN (SELECT t3.id FROM t3 WHERE t3.name LIKE 'x%');
#CLI: ERROR 1062 (23000): Duplicate entry 'NULL' for key 'key0'; expected an empty result
#ERR: - (no error)
