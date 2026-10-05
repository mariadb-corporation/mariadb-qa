# mysqld options required for replay: --innodb_page_size=4K --innodb-buffer-pool-size=5M --innodb_file_per_table=0 --innodb_change_buffering=inserts
CREATE TABLE t (pk INT AUTO_INCREMENT PRIMARY KEY, ci INT, cdt DATETIME, cv VARCHAR(1), KEY ci (ci), KEY cdt (cdt), KEY cv (cv,ci)) ENGINE=InnoDB ROW_FORMAT=REDUNDANT;
INSERT INTO t (ci,cdt,cv) SELECT seq%997, TIMESTAMP'2020-01-01 00:00:00'+INTERVAL seq MINUTE, CHAR(97+seq%26) FROM seq_1_to_20000;
DELIMITER //
CREATE PROCEDURE p() BEGIN DECLARE i INT DEFAULT 30; WHILE i > 0 DO INSERT INTO t (ci,cdt,cv) SELECT seq%997, TIMESTAMP'2020-01-01 00:00:00'+INTERVAL ((seq*7919+i*104729)%20000) MINUTE, CHAR(97+seq%26) FROM seq_1_to_4000; ALTER TABLE t FORCE; SET i = i-1; END WHILE; END//
DELIMITER ;
CALL p();
CHECK TABLE t EXTENDED;
