RESET MASTER;
CREATE TABLE t (c BLOB,c2 DOUBLE (0,0) ZEROFILL,c3 CHAR CHARACTER SET 'utf8' COLLATE 'utf8_bin') ENGINE=InnoDB;
CREATE TABLE t2 (c INT,c2 DOUBLE (0,0) ZEROFILL,c3 FLOAT(0,0) ZEROFILL,KEY(c)) ENGINE=InnoDB;
CREATE TABLE t3 (c TIME KEY,c2 GEOMETRYCOLLECTION,c3 DATE) ENGINE=InnoDB;
# [ERROR] Error reading packet from server: The binlog on the master is missing the GTID 0-2-130 requested by the slave (even though both a prior and a subsequent sequence number does exist), and GTID strict mode is enabled (server_errno=1236)
# [ERROR] Slave I/O: Got fatal error 1236 from master when reading data from binary log: 'The binlog on the master is missing the GTID 0-2-130 requested by the slave (even though both a prior and a subsequent sequence number does exist), and GTID strict mode is enabled', Internal MariaDB error code: 1236
