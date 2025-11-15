CREATE TABLE t (a INT PRIMARY KEY);
INSERT INTO t VALUES (1);
CREATE TRIGGER tr BEFORE INSERT ON t FOR EACH ROW BEGIN END;
SET sql_mode= SIMULTANEOUS_ASSIGNMENT;
UPDATE t SET a = 2;

CREATE DATABASE IF NOT EXISTS db;
CREATE TABLE long_enough_name (
pk INTEGER AUTO_INCREMENT,
col_int_nokey INTEGER,
col_int_key INTEGER,
col_date_key DATE,
col_date_nokey DATE,
col_datetime_key DATETIME,
col_datetime_nokey DATETIME,
col_varchar_key VARCHAR(1),
col_varchar_nokey VARCHAR(1),
PRIMARY KEY (pk),
KEY (col_int_key DESC),
KEY (col_datetime_key),
KEY (col_varchar_key, col_int_key DESC)
) ENGINE=InnoDB;
INSERT IGNORE INTO long_enough_name ( `pk` ) VALUES ( NULL );
DELIMITER $
CREATE TRIGGER e BEFORE INSERT ON long_enough_name FOR EACH ROW BEGIN
  DELETE FROM `partition_by_columns_db`.`PP_C` WHERE `col_varchar_5_utf8_key` < 'jazz';
  INSERT INTO `optimizer_no_indexes_db`.`view_table20_aria_merge` ( `col_char_255_null` ) VALUES ( 'relief' ) ;
  UPDATE IGNORE `partition_by_columns_db`.`PP_L` SET `col_varchar_32_utf8_key` = NULL WHERE `col_varchar_32_latin1_key` > 7 ;
  CALL q () ;
END $
DELIMITER ;
UPDATE long_enough_name SET pk = 2;
SET sql_mode= SIMULTANEOUS_ASSIGNMENT;
UPDATE long_enough_name SET `pk` = 3;

CREATE TABLE t (c INT AUTO_INCREMENT KEY) ENGINE=MyISAM;
CREATE TRIGGER tr BEFORE INSERT ON t FOR EACH ROW INSERT INTO t VALUES (1);
UPDATE t SET c=(SELECT 1 FROM t);

CREATE TABLE t (x INT,a INT KEY AUTO_INCREMENT,b INT,c INT,y INT,d VARCHAR(8000));
CREATE TRIGGER t_bi BEFORE INSERT ON t FOR EACH ROW SET NEW.a=1;
UPDATE t AS A,t AS B SET A.a=1;
