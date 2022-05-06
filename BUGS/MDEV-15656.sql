SET SESSION group_concat_max_len=0;
CREATE TABLE t0 (i INT,KEY USING BTREE (i)) ENGINE=InnoDB;
SET debug_dbug='+d,kill_join_init_read_record';
INSERT INTO t0 VALUES(0xA0C0);
INSERT INTO t0 SELECT DISTINCT i FROM t0;
