CREATE TABLE t1 (a DATETIME DEFAULT CURRENT_TIMESTAMP, b INT);
INSERT INTO t1 () VALUES (),();
SELECT * FROM t1 WHERE IFNULL(b, DEFAULT(a)) IS NOT NULL;

CREATE TABLE t1 (a DATETIME DEFAULT CURRENT_TIMESTAMP, b INT);
INSERT INTO t1 () VALUES (),();
SELECT * FROM t1 WHERE IFNULL(b, DEFAULT(a));

CREATE TABLE t1 (a DATETIME DEFAULT CURRENT_TIMESTAMP);
SELECT * FROM t1 WHERE DEFAULT(a) < 0 ORDER BY BINARY(DES_ENCRYPT('bar' >= 'foo'));

create table t1 (d1 datetime not null);
insert into t1 values ('0000-00-00 00:00:00'), ('0000-00-00 00:00:00');
select avg(d1) over () from t1 group by uuid() with rollup;

create or replace table t1 (d1 datetime not null);
insert into t1 values ('0000-00-00 00:00:00'), ('0000-00-00 00:00:00');
select avg(d1) over () from t1 group by rand() with rollup;
