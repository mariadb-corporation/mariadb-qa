SET GLOBAL innodb_disallow_writes=ON;
# Exit the client, and execute: mysqladmin shutdown, server will hang

SET GLOBAL innodb_disallow_writes=ON;
SHUTDOWN;
