CREATE TABLE t (a INT KEY,b TEXT);
SET gtid_seq_no=1;
SET GLOBAL gtid_strict_mode=1;
RENAME TABLE t TO t4;
