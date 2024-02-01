CHANGE MASTER TO master_host='localhost',master_user='foo';
START SLAVE;
# [ERROR] Slave I/O: error connecting to master 'foo@localhost:3306' - retry-time: 60  maximum-retries: 100000  message: Access denied for user 'foo'@'localhost', Internal MariaDB error code: 1698
