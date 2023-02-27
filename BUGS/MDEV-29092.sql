CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
ALTER TABLE t ADD FOREIGN KEY(c) REFERENCES t(c);
# Then check client for: ERROR 1025 (HY000): Error on rename of './test/#sql-alter-24171f-4' to './test/t' (errno: 150 "Foreign key constraint is incorrectly formed")
# And error log: [ERROR] InnoDB: In ALTER TABLE `test`.`t` has or is referenced in foreign key constraints which are not compatible with the new table definition.
