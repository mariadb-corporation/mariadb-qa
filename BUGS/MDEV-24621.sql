create table t1(f1 int not null primary key, b char(255) CHARACTER SET utf8)engine=innodb;
INSERT INTO t1(f1) SELECT * FROM seq_1_to_1000000;
alter table t1 force, algorithm=inplace;
