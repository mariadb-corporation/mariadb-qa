CREATE TABLE t1 (c YEAR);
CREATE TABLE t2 (c INT);
SELECT * FROM t1 JOIN t2 ON t1.c=t2.c WHERE t1.c<=>5;

CREATE TABLE t (a DATETIME);
SET optimizer_switch='derived_merge=off';
SELECT * FROM (SELECT * FROM t) AS t WHERE a='';

SET optimizer_switch='derived_merge=off,condition_pushdown_for_derived=on';
CREATE TABLE t (a INT);
SELECT * FROM (SELECT a-23 AS a FROM t WHERE a=23) AS t WHERE a='8';
