SET sql_mode='';
CREATE TABLE t (a INT GENERATED ALWAYS AS (1) VIRTUAL,KEY(a)) ENGINE=MyISAM;
INSERT INTO t SELECT * FROM seq_1_to_10;
CREATE TABLE t1 (a CHAR(1),KEY(a)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1);
INSERT INTO t SELECT * FROM seq_1_to_10;
SHUTDOWN;
