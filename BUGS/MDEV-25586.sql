DROP DATABASE test;
SET GLOBAL wsrep_ignore_apply_errors=0;
CREATE USER dummy_user@localhost IDENTIFIED WITH dummy_plugin;
WITH t AS (SELECT * FROM t0 WHERE b=0) SELECT * FROM t0;