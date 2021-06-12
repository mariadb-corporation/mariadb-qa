# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t1 (a TEXT, PRIMARY KEY(a(1871))) ENGINE=InnoDB;
ALTER TABLE t1 MODIFY IF EXISTS b TINYINT AFTER c;

# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t (c1 BLOB,PRIMARY KEY(c1(3072))) ENGINE=InnoDB;
ALTER TABLE t ADD COLUMN j INT;

# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t (c1 TEXT (4000),c2 TEXT (4000),PRIMARY KEY(c1(3072))) ENGINE=InnoDB;
OPTIMIZE TABLE t;
