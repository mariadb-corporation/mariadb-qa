ALTER TABLE mysql.servers DROP COLUMN Owner;
INSERT INTO mysql.servers VALUES(0,0,0,0,0,0,0,0);
FLUSH PRIVILEGES;

alter table mysql.plugin drop column dl;
install soname "ha_example";

CREATE OR REPLACE TABLE mysql.procs_priv (id INT);
INSERT INTO mysql.procs_priv VALUES(0);
CREATE ROLE r;

CREATE OR REPLACE TABLE mysql.procs_priv (id INT) ENGINE=MyISAM;
DROP USER'';

CREATE OR REPLACE TABLE mysql.procs_priv (id INT) ENGINE=MyISAM;
RENAME USER''@''TO''@'''''''''';
