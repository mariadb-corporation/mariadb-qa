CREATE TABLE t (c CHAR(6)) CHARSET=utf8 ENGINE=InnoDB;
RENAME TABLE t TO t.t;  # Where database 't' does not exist
# CLI: ERROR 1025 (HY000): Error on rename of './test/t' to './t/t' (errno: 168 "Unknown (generic) error from engine")

CREATE TABLE t(c INT KEY,c1 CHAR,c3 TIMESTAMP);
RENAME TABLE t TO `......................................................`;
# CLI: ERROR 1025 (HY000): Error on rename of './test/t' to './test/@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@00' (errno: 168 "Unknown (generic) error from engine")

CREATE TABLE t(c INT KEY,c1 BLOB,c2 TEXT);
RENAME TABLE t TO `......................................................`;
# CLI: ERROR 1025 (HY000): Error on rename of './test/t' to './test/@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@00' (errno: 168 "Unknown (generic) error from engine")
# ERR: [ERROR] InnoDB: Operating system error number 36 in a file operation.
# ERR: [ERROR] InnoDB: Error number 36 means 'File name too long'
# ERR: [Note] InnoDB: Some operating system error numbers are described at https://mariadb.com/kb/en/library/operating-system-error-codes/
# ERR: [ERROR] InnoDB: Cannot rename file './test/t.ibd' to './test/@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e.ibd'

CREATE TABLE t (c INT) ENGINE=INNODB PARTITION BY RANGE (c) (PARTITION p1 VALUES LESS THAN (4) DATA DIRECTORY = '/foo' ENGINE = INNODB, PARTITION p2 VALUES LESS THAN (8) DATA DIRECTORY = '/bar' ENGINE = INNODB);
# CLI: ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 168 "Unknown (generic) error from engine")
# ERR: [ERROR] InnoDB: Operating system error number 13 in a file operation. and [ERROR] InnoDB: The error means mariadbd does not have the access rights to the directory.

# ln -s /dev/shm/var /dev/shm/foo  # Neither should exist before running this command, this creates a broken link from foo -> var
CREATE TABLE t (c INT) ENGINE=INNODB PARTITION BY RANGE (c) (PARTITION p1 VALUES LESS THAN (4) DATA DIRECTORY = '/dev/shm/foo' ENGINE = INNODB, PARTITION p2 VALUES LESS THAN (8) DATA DIRECTORY = '/dev/shm/foo' ENGINE = INNODB); 
# CLI: ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 168 "Unknown (generic) error from engine")
# ERR: [ERROR] InnoDB: File /dev/shm/foo/test was not found

CREATE TABLE t (a INT KEY);
RENAME TABLE t TO doesnotexist.t;

CREATE TABLE t1(c1 INT KEY,old1 DOUBLE,new1 DOUBLE,old2 DOUBLE,new2 DOUBLE);
RENAME TABLE t1 TO doesnotexist.t1;

CREATE TABLE t1 (c1 INT) ENGINE=InnoDB PARTITION BY RANGE(c1) SUBPARTITION BY HASH(c1) SUBPARTITIONS 2 (PARTITION p1 VALUES LESS THAN (10));
SET sql_mode='ANSI_QUOTES';
RENAME TABLE t1 TO "t2_new..............................................end";
# CLI: ERROR 1025 (HY000): Error on rename of './test/t1' to './test/t2_new@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@0' (errno: 168 "Unknown (generic) error from engine")
# ERR: [ERROR] InnoDB: Operating system error number 36 in a file operation.
# ERR: [ERROR] InnoDB: Error number 36 means 'File name too long'
# ERR: [Note] InnoDB: Some operating system error numbers are described at https://mariadb.com/docs/server/reference/error-codes/operating-system-error-codes
# ERR: [ERROR] InnoDB: Cannot rename file './test/t1#P#p1#SP#p1sp0.ibd' to './test/t2_new@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002e@002eend#P#p1#SP#p1sp0.ibd'
