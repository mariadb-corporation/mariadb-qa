RENAME TABLE mysql.procs_priv TO mysql.temp;
CREATE USER a IDENTIFIED WITH 'a';

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
CREATE USER a@a;

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
DROP USER a;

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
RENAME USER 'a'@'a' TO 'a'@'a';

CREATE OR REPLACE TABLE mysql.procs_priv (id INT);
DROP USER'';

CREATE OR REPLACE TABLE mysql.procs_priv (id INT);
CREATE USER u1@localhost;
