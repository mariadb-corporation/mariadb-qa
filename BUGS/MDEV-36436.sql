set sql_mode='';
CREATE TABLE t1 (c INT,c2 CHAR AS(CONCAT (0,DAYNAME (0))));
SET SESSION unique_checks=0,foreign_key_checks=0;
INSERT INTO t1 VALUES (1,1);
ALTER IGNORE TABLE t1 ADD y INT,ALGORITHM=COPY;

create table t1(f1 int not null, f2 int default null,f3 int not null)engine=innodb;
insert into t1 values(1, 1, 1);
show create table t1;
ALTER IGNORE TABLE t1 CHANGE IF EXISTS f2 f2 BOOL NULL DEFAULT NULL;
ALTER IGNORE TABLE t1 CHANGE f3 f3 bool null default null;
show create table t1;
