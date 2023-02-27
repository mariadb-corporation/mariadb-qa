# mysqld options that were in use during reduction: --sql_mode=ONLY_FULL_GROUP_BY --performance-schema --performance-schema-instrument='%=on' --default-tmp-storage-engine=MyISAM --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT
USE test;
CREATE TABLE t1(a BIGINT UNSIGNED) ENGINE=InnoDB;
set global innodb_limit_optimistic_insert_debug = 2;
INSERT INTO t1 VALUES(12979);
ALTER TABLE t1 algorithm=inplace, ADD f DECIMAL(5,2);
insert into t1 values (5175,'abcdefghijklmnopqrstuvwxyz');
DELETE FROM t1;
SELECT HEX(a), HEX(@a:=CONVERT(a USING utf8mb4)), HEX(CONVERT(@a USING utf16le)) FROM t1; ;

SET @saved_frequency = @@GLOBAL.innodb_purge_rseg_truncate_frequency;
SET GLOBAL innodb_purge_rseg_truncate_frequency = 1;
CREATE TABLE t ( pk int auto_increment primary key, c01 char(255) not null default repeat('a',255), c02 char(255) default repeat('a',255), c03 char(255) default repeat('a',255), c04 char(255) default repeat('a',255), c05 char(255) not null default repeat('a',255), c06 char(255) default repeat('a',255), c07 char(255) default repeat('a',255), c08 char(255) not null default repeat('a',255), c09 char(255) default repeat('a',255), c10 char(255) default repeat('a',255), c11 char(255) default repeat('a',255), c12 char(255) not null default repeat('a',255)) ENGINE=InnoDB CHARACTER SET ucs2;
INSERT INTO t () VALUES ();
ALTER TABLE t ADD c INT;
BEGIN;
INSERT INTO t () VALUES (),(),(),(),(),(),(),();
ROLLBACK;
DELETE FROM t;
SET GLOBAL innodb_purge_rseg_truncate_frequency = @saved_frequency;
CREATE TABLE tt ENGINE=InnoDB AS SELECT c FROM t;
DROP TABLE t, tt;

CREATE TABLE t (c0 CHAR(255) NOT NULL DEFAULT REPEAT ('',255),c1 CHAR(255) DEFAULT REPEAT ('',255),c2 CHAR(255) DEFAULT REPEAT ('',255),c3 CHAR(255) NOT NULL DEFAULT REPEAT ('',255),c4 CHAR(255) DEFAULT REPEAT ('',255),c6 CHAR(255) DEFAULT REPEAT ('',255),c7 CHAR(255) DEFAULT REPEAT ('',255),c8 CHAR(255) DEFAULT REPEAT ('',255),c9 CHAR(255) NOT NULL DEFAULT REPEAT ('',255)) ENGINE=InnoDB CHARACTER SET ucs2;
INSERT INTO t() VALUES ();
ALTER TABLE t ADD c INT;
BEGIN;
INSERT INTO t() VALUES (),();
DELETE FROM t;
CREATE TABLE tt ENGINE=InnoDB AS SELECT c FROM t;
