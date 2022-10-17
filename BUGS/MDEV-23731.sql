SET SQL_MODE='';
RENAME TABLE mysql.user TO mysql.user_old;
CREATE TABLE mysql.user (host CHAR(100), user CHAR(100)) ENGINE=MERGE;
DROP TABLE mysql.global_priv;
ALTER USER 'a' IDENTIFIED BY '';

RENAME TABLE mysql.user TO mysql.user_bak;
DROP TABLE mysql.global_priv;
CREATE TABLE mysql.user (HOST CHAR,USER CHAR);
CREATE USER m@localhost;

RENAME TABLE mysql.user TO mysql.user_bak;
CREATE TABLE mysql.user (HOST CHAR,USER INT) ENGINE=InnoDB;
DROP TABLE mysql.global_priv;
GRANT PROXY ON a TO b;
