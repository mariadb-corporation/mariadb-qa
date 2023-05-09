SET sql_mode='';
RENAME TABLE mysql.tables_priv TO mysql.tables_priv_bak;
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE mysql.tables_priv SELECT * FROM mysql.tables_priv_bak;
GRANT SELECT ON t TO m@localhost;

SET sql_mode='';
CREATE TABLE t (c INT);
ALTER TABLE mysql.tables_priv DROP COLUMN TIMESTAMP;
GRANT SELECT ON t TO u@localhost;
