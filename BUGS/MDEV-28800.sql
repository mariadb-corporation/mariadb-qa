SET GLOBAL innodb_buffer_pool_size=12*1024*1024;
CREATE TABLE t1 (d DOUBLE) ENGINE=InnoDB;
INSERT INTO t1 VALUES (0x0061),(0x0041),(0x00E0),(0x00C0),(0x1EA3),(0x1EA2),(0x00E3),(0x00C3),(0x00E1),(0x00C1),(0x1EA1),(0x1EA0);
INSERT INTO t1 SELECT t1.* FROM t1,t1 t2,t1 t3,t1 t4,t1 t5,t1 t6;
INSERT INTO t1 SELECT t1.* FROM t1,t1 t2,t1 t3,t1 t4,t1 t5,t1 t6;  # Likely not required for crash. See MDEV-28800 on slowness.
