# Requires standard m/s setup, and basedir/data be on tmpfs /dev/shm
RESET MASTER;
DELETE FROM mysql.user;
FLUSH PRIVILEGES;
# SLAVE ERR: [ERROR] Slave I/O: error reconnecting to master 'repl_user@127.0.0.1:10244' - retry-time: 60  maximum-retries: 100000  message: Host 'localhost' is not allowed to connect to this MariaDB server, Internal MariaDB error code: 1130
