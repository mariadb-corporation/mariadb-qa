CREATE TABLE t (c INT) PARTITION BY RANGE (c) (PARTITION p VALUES LESS THAN (4) DATA DIRECTORY='/foo',PARTITION p2 VALUES LESS THAN (8) DATA DIRECTORY='/bar');
# CLI: ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 168 "Unknown (generic) error from engine")
# ERR: [ERROR] InnoDB: Operating system error number 13 in a file operation.
# ERR: [ERROR] InnoDB: The error means mariadbd does not have the access rights to the directory.

CREATE TABLE t (c INT) ENGINE=Spider PARTITION BY RANGE (c) (PARTITION p1 VALUES LESS THAN (4) DATA DIRECTORY = '/foo' ENGINE = Spider,PARTITION p2 VALUES LESS THAN (8) DATA DIRECTORY = '/bar' ENGINE = Spider);
