SET GLOBAL innodb_defragment_stats_accuracy=1;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (f INT,f2 CHAR(1),KEY k1 (f2),FULLTEXT KEY(f2),FOREIGN KEY(f2) REFERENCES t (f3)) ENGINE=InnoDB;
