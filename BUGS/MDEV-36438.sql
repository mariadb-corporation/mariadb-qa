CREATE TABLE t (id INT PRIMARY KEY) ENGINE=innodb;
ALTER TABLE t MODIFY id CHAR(0);
UPDATE t SET id = 1;

CREATE TABLE t (a TEXT,b CHAR(1) KEY) CHARSET=utf8 ENGINE=InnoDB;
ALTER TABLE t CHANGE COLUMN b c CHAR(0);
UPDATE t SET c=0;

