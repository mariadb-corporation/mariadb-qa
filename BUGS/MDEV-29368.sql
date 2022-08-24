# Repeat 200 to 5000 times for issue to trigger
DROP DATABASE test;  # Only here to ensure clean state on each iteration
CREATE DATABASE test;  # Idem
USE test;  # Idem
SET sql_mode='';
CREATE TABLE ti (a INT NOT NULL, b INT UNSIGNED NOT NULL, c CHAR(45), d VARCHAR(57) NOT NULL, e VARBINARY(48), f VARCHAR(97) NOT NULL, g BLOB, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;
XA START 'a';
XA END 'a';
SET @@max_statement_time=0.0001;
SET SESSION pseudo_slave_mode=1;
XA PREPARE 'a';;
XA COMMIT 'a';  # Only here to ensure the next round of SQL works correctly, not required in actual crash sequence.
