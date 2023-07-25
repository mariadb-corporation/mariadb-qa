SET sql_mode='';
CREATE TABLE t (a INT GENERATED ALWAYS AS (0) VIRTUAL,KEY(a)) ENGINE=MYISAM;
INSERT INTO t SELECT 0 seq_0_to_0;
SET GLOBAL gtid_pos_auto_engines='InnoDB,MEMORY';
INSERT INTO t SELECT 0 seq_0_to_0;
SET GLOBAL gtid_pos_auto_engines='InnoDB';
