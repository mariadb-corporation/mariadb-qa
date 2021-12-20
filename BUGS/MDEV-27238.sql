SET sql_mode='';
CREATE TABLE t (a INT KEY,b INT,KEY(b)) ENGINE=MEMORY;
SET optimizer_trace=1;
INSERT INTO t VALUES (0,0);
SELECT a FROM t WHERE (a,b) in (SELECT @c,@d);
