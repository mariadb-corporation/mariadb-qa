# mysqld options required for replay:  --sql_mode= 
CREATE TABLE t (c INT AUTO_INCREMENT KEY);
SET @@SESSION.insert_id=-0;  # Or -1, -2 etc.
INSERT INTO t VALUES(0);

USE test;
SET @@session.insert_id=0;
CREATE TABLE t (c INT KEY);
INSERT INTO t VALUES (0);
ALTER TABLE t CHANGE c c INT AUTO_INCREMENT;

SET sql_mode='';
CREATE TABLE t (c INT AUTO_INCREMENT KEY) ENGINE=InnoDB;
SET @@SESSION.insert_id=-0;  # Or -1, -2 etc.
INSERT INTO t VALUES(0);

SET SQL_MODE='';
SET GLOBAL stored_program_cache = 0;
SET @start_value=@@GLOBAL.stored_program_cache;
SET SESSION insert_id=@start_value;
INSERT INTO mysql.time_zone VALUES (NULL, 'a');

SET SESSION insert_id=0;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
ALTER TABLE mysql.general_log ADD COLUMN seq INT AUTO_INCREMENT PRIMARY KEY;
SET GLOBAL log_output="TABLE";
SET GLOBAL general_log=1;
INSERT INTO non_existing VALUES (1);

SET SESSION insert_id=FALSE;
INSTALL PLUGIN ARCHIVE SONAME 'ha_archive.so';
CREATE TABLE t (a INT AUTO_INCREMENT,b BLOB,KEY (a)) ENGINE=ARCHIVE;
INSERT INTO t VALUES(0,'');

SET SESSION insert_id=0;
CREATE TABLE t (a SERIAL KEY,b INT);
INSERT INTO t (b) VALUES (1);

CREATE TEMPORARY TABLE t0 (id INT AUTO_INCREMENT KEY,a INT,INDEX (a));
SET SESSION insert_id=0;
INSERT INTO t0 (a) VALUES (0),(0),(0),(0);
