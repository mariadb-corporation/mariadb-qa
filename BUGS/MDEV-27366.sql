SET sql_mode='';
SET join_cache_level=3;
CREATE TABLE t (c BIGINT, d INT, KEY c(c), KEY d(d)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,2),(1,3),(2,0),(3,0),(4,6),(5,0);
SELECT * FROM t,t AS b WHERE t.c=0 AND t.d=b.c AND t.c=b.d;

# Effectively, this is:
SET optimizer_switch='rowid_filter=on'
SET sql_mode='';
SET join_cache_level=3;
CREATE TABLE t (c BIGINT, d INT, KEY c(c), KEY d(d)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,2),(1,3),(2,0),(3,0),(4,6),(5,0);
SELECT * FROM t,t AS b WHERE t.c=0 AND t.d=b.c AND t.c=b.d;
