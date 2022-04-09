CREATE TABLE t1 ( i6 inet6, a1 time, a2 varchar(10));
INSERT INTO t1 VALUES ('::','09:43:12','uw'), ('70:ef59::46:c7b:f:678:bd9f','00:00:00','a');
SELECT group_concat( if(a1, i6, a2) ORDER BY 1) FROM t1;
drop table t1;

CREATE TABLE t1 ( i6 uuid, a1 time, a2 varchar(10));
INSERT INTO t1 VALUES ('ffffffff-ffff-ffff-ffff-fffffffffffe','09:43:12','uw'), (uuid(),'00:00:00','a');
SELECT group_concat( if(a1, i6, a2) ORDER BY 1) FROM t1;
drop table t1;

CREATE OR REPLACE TABLE t1 (i6 inet6, a2 varchar(10));
INSERT INTO t1 VALUES ('::','uw'), (null,'a');
SELECT group_concat(coalesce(i6, a2) ORDER BY 1) FROM t1;
DROP TABLE t1;

CREATE TABLE t(a INET6);
INSERT INTO t VALUES();
SELECT JSON_ARRAYAGG(a ORDER BY a DESC)FROM t;
