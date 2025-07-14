SET sql_mode='';
SET log_bin_trust_function_creators=1;
RENAME TABLE mysql.procs_priv TO mysql.procs_priv_bak;
USE mysql;
CREATE TABLE procs_priv (dummy INT);
CREATE FUNCTION f() RETURNS INT RETURN (SELECT 1 t);
GRANT EXECUTE ON FUNCTION f TO a@b;

SET sql_mode='';
RENAME TABLE mysql.procs_priv TO mysql.procs_priv_bak;
CREATE TABLE mysql.procs_priv (dummy INT) ENGINE=InnoDB;
CREATE FUNCTION f() RETURNS INT RETURN (SELECT 1 t);
GRANT EXECUTE ON FUNCTION f TO a@b;

SET SQL_MODE='';
CREATE PROCEDURE p() BEGIN END;
GRANT EXECUTE ON PROCEDURE p TO USER1@localhost;
CREATE OR REPLACE TABLE mysql.procs_priv (id INT);
DROP PROCEDURE IF EXISTS p;
