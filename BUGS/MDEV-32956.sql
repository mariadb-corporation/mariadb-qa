CREATE TABLE t (a INT);
PREPARE s FROM 'SELECT GROUP_CONCAT(ta.a) FROM t AS ta,t AS tb';
SET NAMES utf8;
EXECUTE s;
