# mysqld options required for replay: --log-bin --sql_mode= 
CREATE TABLE t (a DATE) ENGINE=MEMORY;
INSERT DELAYED INTO t VALUES (now());
RESET MASTER TO 2147483648;
INSERT DELAYED INTO t (a) VALUES (now());
SELECT 1;
