SET GLOBAL init_slave='SELECT 1';
SET GLOBAL profiling=ON;
CHANGE MASTER TO master_host="0.0.0.0";
START SLAVE SQL_THREAD;
SELECT 1;
