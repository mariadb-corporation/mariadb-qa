# mysqld options required for replay: --log_bin 
CREATE PROCEDURE p() FLUSH MASTER;
CALL p();
SET GLOBAL expire_logs_days=1;
SET GLOBAL slave_connections_needed_for_purge=1;
