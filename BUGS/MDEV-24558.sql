CREATE TABLE t(c POINT NOT NULL) ENGINE=InnoDB;
DROP TABLE mysql.innodb_table_stats;
CREATE SPATIAL INDEX i ON t(c);