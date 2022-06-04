# Repeat 1-10 times
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (p1 POINT NOT NULL, p2 POINT NOT NULL, SPATIAL KEY k1 (p1), SPATIAL KEY k2 (p2)) ;
XA START 'x';
INSERT INTO t VALUES (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)')), (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)')), (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)')), (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)'));
XA END 'x';
LOAD INDEX INTO CACHE t1 IGNORE LEAVES;

CREATE TABLE t (fid INT KEY,g POLYGON NOT NULL,a INT,SPATIAL INDEX (g));
XA START 'b';
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
INSERT INTO t VALUES (300,ST_POLYGONFROMTEXT ('POLYGON ((183670 10,2470 10,20 249380,10 254760,183670 10))'),12),(301,ST_POLYGONFROMTEXT ('POLYGON ((10 10,20 10,20 20,10 20,10 10))'),2),(302,ST_POLYGONFROMTEXT ('POLYGON ((110 10,320 310,2550 8520,1059 2590,110 10))'),2),(303,ST_POLYGONFROMTEXT ('POLYGON ((180 160,55620 5610,240 206560,10 285960,180 160))'),2);

SET @save_limit = @@innodb_limit_optimistic_insert_debug;
create table t1(a serial, b geometry not null, spatial index(b)) engine=innodb;
SET GLOBAL innodb_limit_optimistic_insert_debug = 2;
begin;
insert into t1 select seq, Point(1,1) from seq_1_to_5;
rollback;
check table t1;
drop table t1;
SET GLOBAL innodb_limit_optimistic_insert_debug = @save_limit;
