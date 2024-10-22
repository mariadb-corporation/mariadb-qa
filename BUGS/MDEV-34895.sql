CREATE VIEW c AS SELECT 1;
PREPARE s FROM 'ALTER VIEW c AS SELECT 2';
EXECUTE s;
EXECUTE s;

SET @a='';
SET NAMES utf8;
CREATE TABLE t (c INT KEY,c2 BLOB,c3 BLOB);
PREPARE s5 FROM 'DELETE FROM t WHERE c=?';
CREATE TEMPORARY TABLE t (KEYc INT,c CHAR,c2 CHAR,INDEX sec_index (c));
EXECUTE s5 USING @arg;
EXECUTE s5 USING @a;

CREATE TABLE t1 (a int);
INSERT INTO t1 VALUES ('1'),('2');
create view v1 as  SELECT a.* FROM t1 a WHERE (SELECT EXISTS ( SELECT 1 FROM t1 b WHERE b.a = a.a ));
prepare stmt from "select * from v1";
execute stmt;
execute stmt;
drop view v1;
DROP TABLE t1;

SET @a='ABC<DIV style="x:x1ression (javript:alert">DEF';
CREATE TABLE t (c INT,c2 INT) PARTITION BY KEY(c) PARTITIONS 1;
PREPARE s FROM 'DELETE FROM t WHERE c=?';
EXECUTE s USING @SET;
EXECUTE s USING @a;

CREATE TABLE t (c INT);
PREPARE s FROM 'SELECT * FROM t WHERE EXISTS (SELECT 1)';
SET SESSION optimizer_switch='exists_to_in=off';
CREATE TEMPORARY TABLE t (d INT);
EXECUTE s;
SET SESSION optimizer_switch='exists_to_in=on';
EXECUTE s;

SET @s:=REPLACE ("DO ST_ASTEXT (LEFT(@c,@f));","'",'"');
PREPARE s FROM @s;
EXECUTE s;
SET @a=0,@b=0,@c=0;
EXECUTE s;
