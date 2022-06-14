SET sql_mode='',character_set_connection=utf32;
CREATE TABLE t (c ENUM ('','')) CHARACTER SET utf32 ENGINE=InnoDB;
INSERT INTO t VALUES (DATE_FORMAT('2004-02-02','%W'));
