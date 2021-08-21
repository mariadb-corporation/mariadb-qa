CREATE TABLE t(a VARCHAR(16383) CHARACTER SET UTF32, KEY k(a)) ENGINE=InnoDB;
SET SESSION sql_buffer_result=ON;
SET SESSION big_tables=ON;
SELECT DISTINCT COUNT(DISTINCT a) FROM t;

SET SESSION sql_buffer_result=1;
CREATE TABLE t (c INT) ENGINE=InnoDB;
SELECT GROUP_CONCAT(c ORDER BY 2) FROM t;

# Excute via C based client
CREATE TABLE t (grp INT,c CHAR);
SET sql_buffer_result=1;
SELECT grp,GROUP_CONCAT(c ORDER BY 2) FROM t GROUP BY grp;

# Must be executed at the command line
SET sql_buffer_result=1;
CREATE TABLE t (c1 INT,c2 INT);
SELECT c1,GROUP_CONCAT(c2 ORDER BY 2) FROM t GROUP BY c1;
