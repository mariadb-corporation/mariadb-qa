SET collation_connection='tis620_bin';
SET @@session.character_set_server='tis620';
CREATE DATABASE a;
USE a;
CREATE TABLE t(c TEXT,FULLTEXT KEY f(c)) ENGINE=InnoDB;
INSERT INTO t VALUES(100);
ALTER TABLE t ADD (c2 INT);

SET collation_connection='tis620_bin';
SET @@session.character_set_server='tis620';
CREATE DATABASE a;
USE a
CREATE TABLE t1 (col text, FULLTEXT KEY full_text (col)) ENGINE = InnoDB;
INSERT INTO t1 VALUES(7693);
ALTER TABLE t1 ADD (col2 varchar(100) character set latin1);

SET collation_connection='tis620_bin';
SET @session_start_value=@@session.character_set_connection;
SET @@session.character_set_server=@session_start_value;
CREATE DATABASE `�\�\�\`;
USE `�\�\�\`;
CREATE TABLE t(col text,FULLTEXT KEY fullte (col));
INSERT INTO t VALUES(7693);
ALTER TABLE t ADD(col2 CHAR (100));
