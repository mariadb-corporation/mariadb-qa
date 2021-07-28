# mysqld options required for replay: --log-bin
SET GLOBAL binlog_format=STATEMENT,GLOBAL event_scheduler=1;
CREATE EVENT e ON SCHEDULE EVERY 1 SECOND DO INSERT INTO t VALUES (1);
SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;
CREATE TABLE t (c INT);
# Then Check error log for: Event Scheduler: [root@localhost][test.e] Got error 170 "It is not possible to log this statement" from storage engine InnoDB
