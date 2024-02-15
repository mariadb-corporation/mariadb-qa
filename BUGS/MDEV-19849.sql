CREATE TABLE t (c CHAR(6)) CHARSET=utf8 ENGINE=InnoDB;
RENAME TABLE t TO t.t;  # Where database 't' does not exist
# Then observe in client: ERROR 1025 (HY000): Error on rename of './test/t' to './t/t' (errno: 168 "Unknown (generic) error from engine")

CREATE TABLE t(c INT KEY,c1 CHAR,c3 TIMESTAMP);
RENAME TABLE t TO `......................................................`;
# Then observe in client: ERROR 1025 (HY000): Error on rename of './test/t' to './test/@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@00' (errno: 168 "Unknown (generic) error from engine")

CREATE TABLE t (c INT) ENGINE=INNODB PARTITION BY RANGE (c) (PARTITION p1 VALUES LESS THAN (4) DATA DIRECTORY = '/foo' ENGINE = INNODB, PARTITION p2 VALUES LESS THAN (8) DATA DIRECTORY = '/bar' ENGINE = INNODB);
# Observe in client: ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 168 "Unknown (generic) error from engine")
# Observe in error log: [ERROR] InnoDB: Operating system error number 13 in a file operation. and [ERROR] InnoDB: The error means mariadbd does not have the access rights to the directory.

# ln -s /dev/shm/var /dev/shm/foo  # Neither should exist before running this command, this creates a broken link from foo -> var
CREATE TABLE t (c INT) ENGINE=INNODB PARTITION BY RANGE (c) (PARTITION p1 VALUES LESS THAN (4) DATA DIRECTORY = '/dev/shm/foo' ENGINE = INNODB, PARTITION p2 VALUES LESS THAN (8) DATA DIRECTORY = '/dev/shm/foo' ENGINE = INNODB); 
# Observe in client: ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 168 "Unknown (generic) error from engine")
# Observe in error log: [ERROR] InnoDB: File /dev/shm/foo/test was not found
