CREATE EVENT e ON SCHEDULE EVERY 5 HOUR DO SELECT 2;
SET timestamp=100000000;
CREATE EVENT root8 ON SCHEDULE EVERY '2:5' YEAR_MONTH DO SELECT 1;
CREATE EVENT EVENT1 ON SCHEDULE EVERY 15 MINUTE STARTS NOW() ENDS DATE_ADD(NOW(), INTERVAL 5 HOUR) DO BEGIN END;
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e ON SCHEDULE EVERY 1 HOUR STARTS '1999-01-01 00:00:00';
DROP PROCEDURE not_there;
DROP EVENT IF EXISTS non_existing;

DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
SET TIMESTAMP=1;
CREATE EVENT e2 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
CREATE EVENT e3 ON SCHEDULE EVERY 1 MINUTE STARTS DATE_ADD("20100101", INTERVAL 5 MINUTE) ENDS DATE_ADD("20151010", INTERVAL 5 day) COMMENT "c" DO INSERT INTO t VALUES(UNIX_TIMESTAMP(), RAND());
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e1 RENAME TO e4;
CREATE TABLE t2 (c INT);
INSERT INTO t VALUES(0,0,0,0,0,0,0,0,0);

DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO DROP DATABASE BUG52792;
SET TIMESTAMP= 1;
CREATE EVENT root17_1 ON SCHEDULE EVERY '35:25:65' day_minute DO SELECT 1;
CREATE EVENT EVENT3 ON SCHEDULE EVERY 50 + 10 MINUTE STARTS DATE_ADD("20100101", INTERVAL 5 MINUTE) ENDS DATE_ADD("20151010", INTERVAL 5 day) COMMENT "portokala_comment" DO INSERT INTO t_event3 VALUES(UNIX_TIMESTAMP(), RAND());
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e1 RENAME TO e2;
CREATE TABLE mt3 (c1 TINYINT NOT NULL PRIMARY KEY, c2 INT, KEY(c2));
INSERT INTO t VALUES(-4081772719596299475,-28090,'x04ITVo10646Gy82','xdAZ2ZHPnUeM','XqK','JPGQDeeWPwFqv4ayZSv9np4fKSIS','V','mQ',0);

DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO DROP DATABASE BUG52792;
SET TIMESTAMP= 1;
CREATE EVENT e2 ON SCHEDULE EVERY '35:25:65' day_minute DO SELECT 1;
CREATE EVENT e3 ON SCHEDULE EVERY 60 MINUTE STARTS DATE_ADD("20100101", INTERVAL 5 MINUTE) ENDS DATE_ADD("20151010", INTERVAL 5 day) COMMENT "c" DO INSERT INTO t_event3 VALUES(UNIX_TIMESTAMP(), RAND());
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e1 RENAME TO e4;
CREATE TABLE mt3 (c1 TINYINT NOT NULL PRIMARY KEY, c2 INT, KEY(c2));
INSERT INTO t VALUES(0,0,0,0,0,0,0,0,0);

DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO DROP DATABASE BUG52792;
SET TIMESTAMP= 1;
CREATE EVENT e2 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
CREATE EVENT e3 ON SCHEDULE EVERY 60 MINUTE STARTS DATE_ADD("20100101", INTERVAL 5 MINUTE) ENDS DATE_ADD("20151010", INTERVAL 5 day) COMMENT "c" DO INSERT INTO t VALUES(UNIX_TIMESTAMP(), RAND());
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e1 RENAME TO e4;
CREATE TABLE mt3 (c1 TINYINT NOT NULL PRIMARY KEY, c2 INT, KEY(c2));
INSERT INTO t VALUES(0,0,0,0,0,0,0,0,0);

DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO DROP DATABASE BUG52792;
SET TIMESTAMP= 1;
CREATE EVENT e2 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
CREATE EVENT e3 ON SCHEDULE EVERY 60 MINUTE STARTS DATE_ADD("20100101", INTERVAL 5 MINUTE) ENDS DATE_ADD("20151010", INTERVAL 5 day) COMMENT "c" DO INSERT INTO t VALUES(UNIX_TIMESTAMP(), RAND());
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e1 RENAME TO e4;
CREATE TABLE mt3 (c1 TINYINT NOT NULL PRIMARY KEY, c2 INT, KEY(c2));
INSERT INTO t VALUES(0,0,0,0,0,0,0,0,0);

DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
SET TIMESTAMP= 1;
CREATE EVENT e2 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
CREATE EVENT e3 ON SCHEDULE EVERY 60 MINUTE STARTS DATE_ADD("20100101", INTERVAL 5 MINUTE) ENDS DATE_ADD("20151010", INTERVAL 5 day) COMMENT "c" DO INSERT INTO t VALUES(UNIX_TIMESTAMP(), RAND());
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e1 RENAME TO e4;
CREATE TABLE mt3 (c1 TINYINT NOT NULL PRIMARY KEY, c2 INT, KEY(c2));
INSERT INTO t VALUES(0,0,0,0,0,0,0,0,0);

DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
SET TIMESTAMP=1;
CREATE EVENT e2 ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
CREATE EVENT e3 ON SCHEDULE EVERY 60 MINUTE STARTS DATE_ADD("20100101", INTERVAL 5 MINUTE) ENDS DATE_ADD("20151010", INTERVAL 5 day) COMMENT "c" DO INSERT INTO t VALUES(UNIX_TIMESTAMP(), RAND());
SET GLOBAL event_scheduler=TRUE;
ALTER EVENT e1 RENAME TO e4;
CREATE TABLE t2 (c INT);
INSERT INTO t VALUES(0,0,0,0,0,0,0,0,0);

SET @@TIMESTAMP=1;
CREATE EVENT a ON SCHEDULE EVERY '50:20:12:45' DAY_SECOND DO SELECT 1;
CREATE EVENT IF NOT EXISTS d ON SCHEDULE EVERY 2 DAY DO SELECT 2;
SET SESSION profiling=ON;
CREATE EVENT c ON SCHEDULE EVERY 2 SECOND STARTS NOW() ENDS DATE_ADD(NOW(), INTERVAL 5 HOUR) DO BEGIN END;
SET GLOBAL event_scheduler=ON;
ALTER EVENT d ON SCHEDULE EVERY 1 DAY STARTS '2000-01-01 00:00:00';
SELECT SLEEP (3);

SET TIMESTAMP=1040323931;#NOERROR
CREATE EVENT ev2 ON SCHEDULE EVERY 1 SECOND DO INSERT INTO t1  VALUES (SLEEP(0.01),CONCAT('ev2_',CONNECTION_ID()));#NOERROR
create event _user1 on schedule every 10 second do select 42;#NOERROR
SET GLOBAL event_scheduler= ON;#NOERROR
CREATE EVENT event_starts_test ON SCHEDULE EVERY 10 SECOND COMMENT "" DO SELECT 1;#NOERROR
ALTER EVENT event_starts_test ON SCHEDULE AT '2020-02-02 20:00:02';#NOERROR
create event ev_log_general on schedule at now() on completion not preserve do select 'events_logs_test' as inside_event;#NOERROR
create event e1 on schedule every 10 hour do select 1;#NOERROR
DROP EVENT ev2;#NOERROR
CREATE TABLE IF NOT EXISTS `������`(`������` char(1)) DEFAULT CHARSET = sjis engine=TokuDB;#ERROR: 1300 - Invalid utf8 character string: '\x82\xA0\x82\xA0\x82\xA0'

SET TIMESTAMP=1040323931;
CREATE EVENT ev2 ON SCHEDULE EVERY 1 SECOND DO INSERT INTO t1 VALUES (SLEEP (0.01),CONCAT ('ev2_',connection_id()));
CREATE EVENT _user1 ON SCHEDULE EVERY 10 SECOND DO SELECT 42;
SET GLOBAL event_scheduler=ON;
CREATE EVENT event_STARTS_test ON SCHEDULE EVERY 10 SECOND COMMENT "" DO SELECT 1;
ALTER EVENT event_STARTS_test ON SCHEDULE AT '2020-02-02 20:00:02';
CREATE EVENT ev_log_general ON SCHEDULE at NOW() ON completion NOT preserve DO SELECT 'events_logs_test' AS inside_event;
CREATE EVENT e1 ON SCHEDULE EVERY 10 HOUR DO SELECT 1;
DROP EVENT ev2;
CREATE TABLE IF NOT EXISTS ������ (������ CHAR(1)) DEFAULT CHARSET=sjis ENGINE=TokuDB;

CREATE EVENT EVENT1 ON SCHEDULE EVERY 15 MINUTE STARTS NOW() ENDS DATE_ADD(NOW(), INTERVAL 5 HOUR) DO BEGIN END;
SET default_storage_engine=MyISAM;
SET TIMESTAMP=1000000012;
CREATE EVENT root10 ON SCHEDULE EVERY '20:5' DAY_HOUR DO SELECT 1;
CREATE EVENT event_STARTS_test ON SCHEDULE EVERY 20 SECOND STARTS '2020-02-02 20:00:02' ENDS '2022-02-02 20:00:02' DO SELECT 2;
SET GLOBAL event_scheduler='ON';
DROP EVENT IF EXISTS EVENT1;
CREATE DATABASE RocksDBtest;
CREATE TABLE infoschema_buffer_test (col1 INT) ENGINE=RocksDB;
DROP DATABASE RocksDBtest;
