RESET MASTER;
SET GLOBAL require_secure_transport=1;
# [ERROR] Slave I/O: error reconnecting to master 'repl_user@127.0.0.1:3306' - retry-time: 60  maximum-retries: 100000  message: Connections using insecure transport are prohibited while --require_secure_transport=ON. Internal MariaDB error code: 3159
