SET sql_mode='';
CREATE TABLE t (a INT(1) AUTO_INCREMENT,KEY(a))PARTITION BY HASH (a) PARTITIONS 3;
CREATE TRIGGER au AFTER UPDATE ON t FOR EACH ROW SELECT * FROM t INTO @var;
REPLACE INTO t PARTITION (p0) VALUES (1);

create table t (pk int auto_increment primary key) partition by hash(pk) partitions 2;
create trigger tr before insert on t for each row set @a=1;
insert into t partition (p1) values (1);
