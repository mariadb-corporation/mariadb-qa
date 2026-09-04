# Requires MTR & Galera; ref bug report for MTR testcase
CREATE TABLE p (id INT PRIMARY KEY, v INT) ENGINE=InnoDB;
CREATE TABLE c (id INT PRIMARY KEY, pid INT NOT NULL, KEY k (pid), FOREIGN KEY (pid) REFERENCES p (id)) ENGINE=InnoDB;
INSERT INTO p VALUES (1, 0), (2, 0);
INSERT INTO c VALUES (1, 1);
BEGIN;
UPDATE p SET v = v + 1 WHERE id = 1;
SET SESSION max_statement_time = 1;
UPDATE c SET pid = 2 WHERE id = 1;
ROLLBACK;
DROP TABLE c;
DROP TABLE p;
