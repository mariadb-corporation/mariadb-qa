# mysqld options required for replay:  --innodb-read-only
SET GLOBAL innodb_encryption_threads=0;
SHUTDOWN;
