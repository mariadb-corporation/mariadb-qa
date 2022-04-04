CREATE TABLE t (a INT AUTO_INCREMENT KEY,b FLOAT(5,3),c BLOB (1),d CHAR(1),e TEXT) ENGINE=InnoDB;
ALTER TABLE t ADD UNIQUE id USING HASH (a);

# Then check error log for: Incorrect information in file: './test/#sql-alter-....frm'
