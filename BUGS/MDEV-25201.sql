SET GLOBAL wsrep_replicate_myisam= ON;
CREATE TEMPORARY TABLE t1 (i INT, PRIMARY KEY pk (i)) ENGINE=MyISAM;
PREPARE stmt FROM "INSERT INTO t1 (id) SELECT * FROM (SELECT 4 AS i) AS y";
INSERT INTO t1 VALUES(4);

CREATE TABLE t (a INT KEY);
SET GLOBAL wsrep_replicate_myisam=ON;
PREPARE stmt FROM 'UPDATE mysql.user SET authentication_string=(?) WHERE USER=?';
INSERT INTO t VALUES (0xA7C3);
