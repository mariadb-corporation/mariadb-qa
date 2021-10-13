RENAME TABLE mysql.procs_priv TO mysql.temp;
CREATE USER a IDENTIFIED WITH 'a';

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
CREATE USER a@a;

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
DROP USER a;
