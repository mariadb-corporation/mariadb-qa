ENAME TABLE mysql.columns_priv TO mysql.columns_priv_bak;
CREATE TABLE mysql.columns_priv SELECT * FROM mysql.columns_priv_bak;  # "LIKE" instead of "SELECT * FROM" does not lead to a crash, and neither does ALTER TABLE mysql.columns_priv ENGINE=InnoDB instead of the first two commands. There are 0 rows in the table.
CREATE TABLE t (c INT) ENGINE=InnoDB;
GRANT UPDATE (c) ON t TO a@localhost;
