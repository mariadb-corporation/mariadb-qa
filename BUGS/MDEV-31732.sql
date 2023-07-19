CREATE TABLE t (a INT) ENGINE=MyISAM;
SET GLOBAL aria_encrypt_tables=1;
SET GLOBAL encrypt_tmp_disk_tables=1;
SET big_tables=1;
EXPLAIN SELECT * FROM t WHERE a in (SELECT MAX(a) FROM t);
