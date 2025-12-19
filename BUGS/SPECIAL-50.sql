CREATE TABLE mysql.host (c INT) ENGINE=InnoDB;
FLUSH PRIVILEGES;
# CLI: ERROR 1728 (HY000): Cannot load from mysql.host. The table is probably corrupted
# ERR: [ERROR] mariadbd: Cannot load from mysql.host. The table is probably corrupted
# ERR: [ERROR] Fatal error: Can't open and lock privilege tables: Cannot load from mysql.host. The table is probably corrupted
