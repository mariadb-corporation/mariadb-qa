SET @@character_set_server=1;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (c1 BLOB);
ALTER TABLE t ADD c CHAR(30) CHARACTER SET latin1 DEFAULT CONCAT ('ÃŸ');

# Then check error log for: Incorrect information in file: ... #sql-alter ... .frm
