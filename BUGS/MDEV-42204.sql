# Then run the dumped script in the CLI: mariadb --binary-mode test < /tmp/ctx.sql
CREATE TABLE parent (id INT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE child (id INT PRIMARY KEY, pid INT, FOREIGN KEY (pid) REFERENCES parent (id)) ENGINE=InnoDB;
INSERT INTO parent VALUES (1);
INSERT INTO child VALUES (1,1);
SET optimizer_record_context=ON;
SELECT * FROM child;
SET optimizer_record_context=OFF;
SELECT context INTO DUMPFILE '/tmp/ctx.sql' FROM information_schema.OPTIMIZER_CONTEXT;
DROP TABLE child, parent;
#CLI: the script gives ERROR 1005 (HY000): Can't create table `test`.`child` (errno: 150 "Foreign key constraint is incorrectly formed"); expected no error
#ERR: - (no error)
