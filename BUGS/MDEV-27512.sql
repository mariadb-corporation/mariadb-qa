CREATE TABLE t1(fld1 int,key key1(fld1)) engine=innodb;
XA START 'a';
insert into t1 values(3819);
insert t1 values ('aaaaaa cccccc');
XA END 'a';
XA COMMIT 'a' ONE PHASE;
DELETE FROM t1;
