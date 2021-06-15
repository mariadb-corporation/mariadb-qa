SET SESSION old_mode='';
ALTER TABLE mysql.innodb_index_stats MODIFY stat_description VARCHAR(1024) COLLATE utf8_bin;
CREATE TABLE t (a INT) ENGINE=InnoDB;

SET SESSION old_mode='';
CREATE TABLE t (a INT) ENGINE=InnoDB;
ALTER TABLE mysql.innodb_index_stats MODIFY stat_description VARCHAR(1024) COLLATE utf8_bin;
DROP TABLE t;

SET sql_mode='';
CREATE TABLE t (a ENUM ('','') DEFAULT'');
SET SESSION old_mode=no_progress_info;
ALTER TABLE mysql.innodb_index_stats MODIFY stat_description VARCHAR(1024) COLLATE utf8_bin;
INSERT INTO t VALUES (0,0,36,'','','','');
