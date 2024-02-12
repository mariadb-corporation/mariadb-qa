# require_secure_transport is OFF by default > RESET MASTER > require_secure_transport=1 > error 3159
RESET MASTER;
SET GLOBAL require_secure_transport=1;
# [ERROR] Slave I/O: error reconnecting to master 'repl_user@127.0.0.1:3306' - retry-time: 60  maximum-retries: 100000  message: Connections using insecure transport are prohibited while --require_secure_transport=ON. Internal MariaDB error code: 3159

SET sql_mode='',old_passwords=1;
GRANT ALL PRIVILEGES ON test_user_db.* TO''@'LOCALHOST' IDENTIFIED BY 'deST_PASSWD';
RESET MASTER;
DROP TABLE IF EXISTS t;
CREATE TABLE Ｔ６ (Ｃ１ ENUM ('龔','龖','龗'),INDEX (Ｃ１)) DEFAULT CHARSET=utf8;
CREATE FUNCTION f (x INT,y INT) RETURNS INT RETURN x + y;
CREATE TABLE t (f CHAR(1),f2 VARCHAR(1),PRIMARY KEY(f,f2));
# [ERROR] Slave I/O: error connecting to master 'repl_user@127.0.0.1:10512' - retry-time: 60  maximum-retries: 100000  message: Connections using insecure transport are prohibited while --require_secure_transport=ON. Internal MariaDB error code: 3159

RESET MASTER;
DROP PROCEDURE IF EXISTS sp1;
SET @@global.require_secure_transport=TRUE;
CREATE TABLE m1(c1 MEDIUMINT ,c2 VARCHAR(1) ,c3 INT(1) ,c4 VARCHAR(1) NOT NULL PRIMARY KEY,c5 MEDIUMINT NOT NULL UNIQUE KEY,c6 DECIMAL(0,0) NOT NULL DEFAULT 3.141592);
create TABLE t1 (a varchar(1));
