CREATE DEFINER=root@localhost EVENT e1 ON SCHEDULE EVERY '1' SECOND COMMENT 'a' DO DELETE FROM t;
SELECT SLEEP(0.2);
CREATE DEFINER=root@localhost EVENT e2 ON SCHEDULE EVERY '1' SECOND COMMENT 'a' DO DELETE FROM t;
SELECT SLEEP(0.2);
CREATE DEFINER=root@localhost EVENT e3 ON SCHEDULE EVERY '1' SECOND COMMENT 'a' DO DELETE FROM t;
SELECT SLEEP(0.2);
CREATE DEFINER=root@localhost EVENT e4 ON SCHEDULE EVERY '1' SECOND COMMENT 'a' DO DELETE FROM t;
SELECT SLEEP(0.1);
CREATE DEFINER=root@localhost EVENT e4 ON SCHEDULE EVERY '1' SECOND COMMENT 'a' DO DELETE FROM t;
SET GLOBAL event_scheduler=ON;
CREATE TABLE t (id INT);
INSERT INTO t VALUES (1),(1);
SET GLOBAL innodb_buffer_pool_size=21474836480;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=134217728;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=21474836480;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=134217728;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=21474836480;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=134217728;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=21474836480;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=134217728;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=21474836480;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=134217728;
SELECT SLEEP(3);
SET GLOBAL innodb_buffer_pool_size=21474836480;
SELECT SLEEP(3);
