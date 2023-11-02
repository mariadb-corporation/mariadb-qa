# mysqld options required for replay: --log-bin
SHOW BINLOG EVENTS FROM 500;

# mysqld options required for replay: --log-bin
RESET MASTER;
DROP TABLE IF EXISTS t1;
CREATE TABLE t1 (c INT) ENGINE=MEMORY;
CREATE TABLE t2 (d INT) ENGINE=MyISAM;
SHOW BINLOG EVENTS FROM 504;
