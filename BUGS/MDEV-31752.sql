CREATE TABLE t (a INET6);
SET character_set_connection=ucs2;
SET optimizer_trace=1;
SELECT * FROM t WHERE (SELECT a FROM t) IN ('','');

CREATE TABLE t (i INT);
SET optimizer_trace=1;
SELECT 1 FROM t WHERE EXISTS (SELECT 1) IN (SELECT 1 FROM t);
