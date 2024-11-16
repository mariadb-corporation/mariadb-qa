SET MAX_HEAP_TABLE_SIZE= 32768;
CREATE TABLE t (a INT, b INT, KEY (a));
INSERT INTO t VALUES (1,3),(0,6),(146,30),(7,2),(8,5),(2,4),(0,1),(175,74),(7,1),(1,9), (2,3),(8,0),(9,0),(NULL,9),(NULL,8),(27,1);
SELECT * FROM t WHERE (a, b) NOT IN (SELECT t1.a, t2.b FROM t AS t1, t AS t2);

SET @@session.max_heap_table_size=32768;
SET @@optimizer_switch='partial_match_table_scan=off,in_to_exists=off';
CREATE TABLE t (c1 INT, c2 INT);
INSERT INTO t VALUES (2,NULL),(2,NULL);
INSERT INTO t VALUES (2,0),(2,1);
SELECT * FROM t WHERE (3,3) NOT IN (SELECT * FROM t);
