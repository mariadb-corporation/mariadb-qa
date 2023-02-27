CREATE PROCEDURE p () SELECT * FROM t WHERE (c) IN (SELECT c FROM t);
SET @@optimizer_switch='semijoin=off,in_to_exists=off';
CREATE TABLE t (c INT) ENGINE=InnoDB;
CALL p ();
CREATE TEMPORARY TABLE t (c BLOB) ENGINE=InnoDB;
CALL p ();
