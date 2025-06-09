CREATE TABLE t (i INT) DATA DIRECTORY='/tmp',ENGINE=InnoDB;  # No error
CREATE TABLE t (i INT) DATA DIRECTORY='/tmp',ENGINE=InnoDB;  # Second exec fails
# CLI: ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 184 "Tablespace already exists")
# ERR: [ERROR] InnoDB: Operating system error number 17 in a file operation.
# ERR: [ERROR] InnoDB: Error number 17 means 'File exists'
# ERR: [Note] InnoDB: The file '/tmp/test/t.ibd' already exists though the corresponding table did not exist in the InnoDB data dictionary. You can resolve the problem by removing the file.
# ERR: [ERROR] InnoDB: Cannot create file '/tmp/test/t.ibd'
