SET GLOBAL max_join_size=0;
SELECT (@id:=Id) FROM information_schema.processlist WHERE User='repl_user';
KILL QUERY @id;
# [ERROR] Slave I/O: The slave I/O thread stops because a fatal error is encountered when it try to get the value of SERVER_ID variable from master. Error: The SELECT would examine more than MAX_JOIN_SIZE rows; check your WHERE and use SET SQL_BIG_SELECTS=1 or SET MAX_JOIN_SIZE=# if the SELECT is okay, Internal MariaDB error code: 1104
