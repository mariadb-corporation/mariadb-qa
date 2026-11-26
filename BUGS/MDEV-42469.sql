CREATE TABLE t1 (a INT) ENGINE=InnoDB PARTITION BY LIST (a) (PARTITION p0 VALUES IN (1), PARTITION p1 VALUES IN (2));
CREATE TABLE t2 (a INT) ENGINE=InnoDB;
INSERT INTO t2 VALUES (1), (3);
ALTER TABLE t1 EXCHANGE PARTITION p0 WITH TABLE t2 WITHOUT VALIDATION;
CHECK TABLE t1;
#CLI: CHECK TABLE gives "Partition p0 returned error" and "Unknown - internal error 160 during operation"; expected a message about the row that fits no partition
#ERR: [Warning] Table `test`.`t1` was altered WITHOUT VALIDATION: the table might be corrupted
