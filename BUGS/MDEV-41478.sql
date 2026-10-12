SET NAMES utf8mb4;
CREATE TABLE t1 (a CHAR(10) COLLATE utf8mb4_unicode_nopad_ci, PRIMARY KEY (a)) ENGINE=InnoDB PARTITION BY KEY (a) PARTITIONS 8;
INSERT IGNORE INTO t1 VALUES ('a'),('ä'),('ａ');
SELECT COUNT(*) FROM t1;
#CLI: 3; expected 1
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t2 (a CHAR(10) COLLATE utf8mb4_unicode_nopad_ci) PARTITION BY KEY (a) PARTITIONS 8;
INSERT INTO t2 VALUES ('a'),('ä'),('ａ');
SELECT COUNT(*) FROM t2 WHERE a='ä';
#CLI: 1; expected 3
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t3 (a CHAR(10) COLLATE utf8mb4_unicode_nopad_ci, UNIQUE (a) USING HASH);
INSERT IGNORE INTO t3 VALUES ('a'),('ä'),('ａ');
SELECT COUNT(*) FROM t3;
#CLI: 3; expected 1
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t1 (a CHAR(10) COLLATE utf8mb4_unicode_nopad_ci, UNIQUE (a) USING HASH) ENGINE=InnoDB;
INSERT IGNORE INTO t1 VALUES ('a'),('ä'),('ａ');
SELECT COUNT(*) FROM t1;
#CLI: 3; expected 1
#ERR: - (no error)
