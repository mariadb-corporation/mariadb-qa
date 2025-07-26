SET GLOBAL init_slave='a';
CHANGE MASTER TO master_host='a',master_log_file='a';
START SLAVE SQL_THREAD;
# ERR: [ERROR] Slave SQL: Slave SQL thread aborted. Can't execute init_slave query due to error code 1064: You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'a' at line 1, Internal MariaDB error code: 4226
