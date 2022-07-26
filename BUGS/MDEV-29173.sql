# mysqld options required for replay: --log-bin --binlog_format=ROW
CREATE TABLE t (a INT,c CHAR(0) AS (DATE_FORMAT(a,1))) ENGINE=InnoDB;
CREATE TRIGGER tr AFTER INSERT ON t FOR EACH ROW SET @a=0;
INSERT INTO t VALUES (),();
