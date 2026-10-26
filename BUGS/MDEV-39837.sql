CREATE TABLE t1 (a INT PRIMARY KEY, b INT, c INT AS (b + 1) VIRTUAL, KEY (c)) ENGINE=InnoDB;
INSERT INTO t1 (a, b) VALUES (1, 1);
SET GLOBAL innodb_purge_batch_size= 1;
DELIMITER //
CREATE PROCEDURE p1(n INT) BEGIN DECLARE i INT DEFAULT 0; WHILE i < n DO UPDATE t1 SET b = b + 1; SET i = i + 1; IF i % 10 = 0 THEN SET GLOBAL innodb_max_purge_lag_wait= 0; END IF; END WHILE; END//
DELIMITER ;
CALL p1(100000);
SET GLOBAL innodb_max_purge_lag_wait= 0;
#CLI: - (no error; on a debug build, mariadbd RSS grows by about 1.6 kB per purge batch and is not freed)
#ERR: - (no error)
