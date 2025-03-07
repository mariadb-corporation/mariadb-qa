CREATE PROCEDURE p() SELECT * FROM (SELECT 1 FROM mysql.user) AS a;
SET SESSION optimizer_switch="derived_merge=OFF";
CALL p();
SET SESSION optimizer_switch="derived_merge=ON";
CALL p();

CREATE TABLE t (id int PRIMARY KEY) ENGINE=InnoDB;
SET @@SESSION.OPTIMIZER_SWITCH="derived_merge=OFF";
CREATE TEMPORARY TABLE t2 (c1 VARBINARY(2)) BINARY CHARACTER SET 'latin1' PRIMARY KEY(c1)) ENGINE=MEMORY;
SET @cmd:="SELECT * FROM (SELECT * FROM t) AS a";
PREPARE stmt FROM @cmd;
EXECUTE stmt;
SET @@SESSION.OPTIMIZER_SWITCH="derived_merge=ON";
EXECUTE stmt;

CREATE TABLE t (c FLOAT(0,0) ZEROFILL,c2 INT,c3 REAL(0,0) ZEROFILL,KEY(c));
SET SESSION optimizer_switch='derived_merge=OFF';
CREATE PROCEDURE p2 (OUT i1 TEXT CHARACTER SET 'latin1' COLLATE 'latin1_bin',OUT i2 INT UNSIGNED) DETERMINISTIC NO SQL SELECT * FROM (SELECT c3 FROM t) AS a1;
CALL p2 (@a,@a);
DROP TABLE t;
SET SESSION optimizer_switch='derived_merge=on';
CREATE TABLE t (c INT UNSIGNED ZEROFILL,c2 INT,c3 BLOB,KEY(c));
CALL p2 (@b,@b);
