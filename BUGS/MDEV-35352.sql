create table tst(val json);
insert into tst values('{}');
select t.val<=>json_extract('[]','$') from tst t;

select '[]'<=>json_extract('[]','$')

CREATE TABLE t1 (b VARCHAR(80));
INSERT INTO t1 VALUES ("Hello"),("World"), ("This");
select * from t1 where b<=>json_extract(1,'$');
drop table t1;

SELECT''<=>JSON_EXTRACT('',JSON_OBJECT (1,'',1,1),'');
