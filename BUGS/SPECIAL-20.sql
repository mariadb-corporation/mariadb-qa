# Requires standard m/s setup
SET sql_mode='';
RESET MASTER;
CREATE TABLE t1 (a SMALLINT UNSIGNED,b MEDIUMINT UNSIGNED,c CHAR(1),d VARBINARY(1),e VARBINARY(1),f CHAR (1),g MEDIUMBLOB NOT NULL,h LONGBLOB,id BIGINT NOT NULL,KEY(b),KEY(e),PRIMARY KEY(id)) ENGINE=Aria;
INSERT INTO t1 VALUES (791437105999006756,8568917,'abcde','abcde','abcde','abcde','abcde','abcde',14);
# [Note] Slave I/O thread: Failed reading log event, reconnecting to retry, log 'binlog.000001' at position 959; GTID position '0-1-3'
# [ERROR] Error reading packet from server: Error: connecting slave requested to start from GTID 0-1-3, which is not in the master's binlog (server_errno=1236)
# Slave I/O: Got fatal error 1236 from master when reading data from binary log: 'Error: connecting slave requested to start from GTID 0-1-3, which is not in the master's binlog', Internal MariaDB error code: 1236
