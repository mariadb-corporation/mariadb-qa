CREATE TABLE ti (a INT UNSIGNED, b SMALLINT, id BIGINT NOT NULL, KEY(b), PRIMARY KEY(id)) ENGINE=InnoDB;
CREATE TABLE tm (a INT PRIMARY KEY, b MEDIUMTEXT) ENGINE=MyISAM;
START TRANSACTION;
INSERT INTO tm SET b=NULL, a=2;
SET sql_mode=only_full_group_by;
INSERT INTO ti VALUES (1,2,4);
SET GLOBAL wsrep_max_ws_rows=2;
UPDATE tm AS t1, ti AS t2 SET t1.a=t1.a * 2, t2.a=t2.a * 2;
UPDATE tm AS t1, ti AS t2 SET t1.a=t1.a * 2, t2.a=t2.a * 2;
