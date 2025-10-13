CREATE TABLE mysql.host (c INT);
FLUSH PRIVILEGES;
# CLI: ERROR 1105 (HY000): Fatal error: mysql.host table is damaged or in unsupported 3.20 format
# ERR: [ERROR] Can't open and lock privilege tables: Cannot load from mysql.host. The table is probably corrupted
# Expected, ref https://mariadb.com/docs/server/reference/system-tables/the-mysql-database-tables/obsolete-mysql-database-tables/mysql-host-table : 'This table is no longer used. This table is no longer created. However if the table is created it will be used.'
