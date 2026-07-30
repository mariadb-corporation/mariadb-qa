CREATE TABLE t1 ( c1 set('') , c2 decimal , c3 int(11) , c4 smallint(6) , KEY idx1 (c2));
INSERT INTO t1 (c1,c2) VALUES (+ 1,1),(+ 1,2);
SELECT JSON_OBJECTAGG(CAST(c2 AS CHAR),JSON_OBJECT('',c4)) j FROM t1;
