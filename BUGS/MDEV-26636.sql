# Sporadic. Loop till crash is seen.
SET GLOBAL innodb_defragment_stats_accuracy=1;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0);
ALTER TABLE t ENGINE=InnoDB;
ALTER TABLE t ENGINE=InnoDB;
ALTER TABLE t ENGINE=InnoDB;
ALTER TABLE t ENGINE=InnoDB;
DROP TABLE t;
