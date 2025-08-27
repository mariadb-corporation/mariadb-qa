USE test;
##SYSTEM rm -Rf /tmp/test   # Required, but disabled for safety
##SYSTEM mkdir -p /tmp/test
##SYSTEM touch /tmp/test/t.ibd
CREATE TABLE t(c INT) DATA DIRECTORY='/tmp';
# CLI: ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 184 "Tablespace already exists")
# ERR: [ERROR] InnoDB: Operating system error number 17 in a file operation.
# ERR: [ERROR] InnoDB: Error number 17 means 'File exists'
# ERR: [Note] InnoDB: The file '/tmp/test/t.ibd' already exists though the corresponding table did not exist in the InnoDB data dictionary. You can resolve the problem by removing the file.
# ERR: [ERROR] InnoDB: Cannot create file '/tmp/test/t.ibd'

USE test;
##SYSTEM rm -Rf /tmp/test
##SYSTEM touch /tmp/test
CREATE TABLE t(c INT) DATA DIRECTORY='/tmp';
# ERR: [ERROR] InnoDB: Operating system error number 20 in a file operation.
# ERR: [ERROR] InnoDB: Error number 20 means 'Not a directory'
# ERR: [Note] InnoDB: Some operating system error numbers are described at https://mariadb.com/kb/en/library/operating-system-error-codes/
# ERR: [ERROR] InnoDB: Operating system error number 20 in a file operation.
# ERR: [ERROR] InnoDB: Error number 20 means 'Not a directory'
# ERR: [Note] InnoDB: Some operating system error numbers are described at https://mariadb.com/kb/en/library/operating-system-error-codes/
# ERR: [ERROR] InnoDB: Cannot create file '/tmp/test/t.ibd'
