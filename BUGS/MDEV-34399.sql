CREATE TABLE t (c1 INT PRIMARY KEY,c2 INT,FOREIGN KEY(c2) REFERENCES t (c1)) ENGINE=InnoDB;
ALTER TABLE t DROP PRIMARY KEY;
# CLI: ERROR 1025 (HY000): Error on rename of './test/#sql-alter-2ff04a-4' to './test/t' (errno: 150 "Foreign key constraint is incorrectly formed")
# ERR: [ERROR] InnoDB: In ALTER TABLE `test`.`t` has or is referenced in foreign key constraints which are not compatible with the new table definition.
