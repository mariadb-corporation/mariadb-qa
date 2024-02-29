# mysqld options required for replay:  --max_allowed_packet=33554432
SET sql_mode='', aria_repair_threads=2;
CREATE TEMPORARY TABLE t (b TEXT, INDEX s(b(3000))) ROW_FORMAT=DYNAMIC ENGINE=Aria;
INSERT INTO t VALUES (REPEAT ('a',33554428));
CREATE TABLE ti LIKE t;
INSERT INTO ti SELECT * FROM t;
