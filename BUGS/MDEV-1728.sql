XA START 'a';
DELETE FROM mysql.innodb_index_stats;
SET SESSION pseudo_slave_mode=1;
XA END 'a';
CREATE TABLE t (a INT) ENGINE=InnoDB;
XA PREPARE 'a';
DROP DATABASE test;
