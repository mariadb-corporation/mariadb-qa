SET sql_mode='',character_set_connection=utf32;
CREATE TABLE t (c ENUM ('','')) CHARACTER SET utf32 ENGINE=InnoDB;
INSERT INTO t VALUES (DATE_FORMAT('2004-02-02','%W'));

SET collation_connection=utf32_unicode_520_ci;
CREATE TABLE t (a SET('') CHARACTER SET utf32);
INSERT INTO t VALUES (DATE_FORMAT(0,0));
