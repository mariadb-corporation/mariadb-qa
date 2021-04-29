SET GLOBAL wsrep_ignore_apply_errors=1;
CREATE TABLE t1 (a CHAR(1));
CREATE TABLE t1 (a CHAR(1));
SHOW PROCEDURE STATUS WHERE db = 'test';
SET GLOBAL read_only=1;