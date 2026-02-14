CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
HANDLER t OPEN AS a;
DROP TABLE t;
CREATE TABLE t (c INT);
HANDLER t OPEN;
HANDLER t READ FIRST;
# CLI: ERROR 1412 (HY000): Table definition has changed, please retry transaction
# ERR: [ERROR] mysql_ha_read: Got error 159 when reading table 't'
# perror: MariaDB error code 159: The table changed in the storage engine
