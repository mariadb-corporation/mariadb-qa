SET optimizer_trace='enabled=on';
CREATE TABLE t1 (a int);
INSERT INTO t1 VALUES (1),(2),(3);
SELECT * FROM t1 WHERE a IN (SELECT 1 a FROM t1 WHERE EXISTS (select 1));

CREATE TABLE t (i INT);
SET optimizer_trace=1;
SELECT 1 FROM t WHERE EXISTS (SELECT 1) IN (SELECT 1 FROM t);

CREATE TABLE t (a INET6);
SET character_set_connection=ucs2;
SET optimizer_trace=1;
SELECT * FROM t WHERE (SELECT a FROM t) IN ('','');

CREATE TABLE t (pk INT, a int, b char(1), key (a), key(b), primary key (pk));
INSERT INTO t VALUES (1,100,'s'),(2,200,'x'),(3,300,'c'),(4,400,'v');
SET optimizer_max_sel_arg_weight= 1, optimizer_trace= 'enabled=on';
SELECT * FROM t WHERE a BETWEEN 7 AND 100 AND b BETWEEN 'a' AND 'z' OR a = 1 OR pk > 8 AND pk < 10;

CREATE TABLE t1 (pk INT PRIMARY KEY, a INT, b INT, KEY(b, a));
INSERT INTO t1 VALUES (1,1,0),(2,2,3),(3,3,0);
SET optimizer_switch='not_null_range_scan=on';
SET optimizer_max_sel_arg_weight=1;
SET optimizer_trace='enabled=on';
SELECT pk FROM t1 WHERE b >= 1 AND a = pk;

CREATE TABLE t1 (a INT, b INT, KEY(b, a));
INSERT INTO t1 VALUES (1,0),(2,3),(3,0);
SET optimizer_switch='not_null_range_scan=on';
SET optimizer_max_sel_arg_weight=1;
SET optimizer_trace='enabled=on';
SELECT COUNT(*) FROM t1 t1a JOIN t1 t1b ON t1a.a = t1b.a WHERE t1a.b >= 1;
