CREATE TABLE t (a INT KEY,b CHAR(0),c TEXT)Engine=InnoDB;
ALTER TABLE t MODIFY a CHAR(0);
SELECT * FROM t;
SELECT * FROM t WHERE a IN (0x0ffffffffffffffe,0x0fffffffffffffff);
