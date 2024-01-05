# mysqld options required for replay:  --innodb-force-recovery=6
SET GLOBAL innodb_truncate_temporary_tablespace_now=1;
