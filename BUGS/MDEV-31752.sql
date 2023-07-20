CREATE TABLE t (a INET6);
SET character_set_connection=ucs2;
SET optimizer_trace=1;
SELECT * FROM t WHERE (SELECT a FROM t) IN ('','');
