SET storage_engine=MEMORY;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);

SET storage_engine=InnoDB;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);

SET storage_engine=MyISAM;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);

SET storage_engine=Aria;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);