SET SESSION wsrep_osu_method=RSU;
CREATE TABLE t0 (a INT,b INT);
SET SESSION wsrep_osu_method=NBO;
INSERT INTO t0 VALUES();
ALTER TABLE t0 LOCK=EXCLUSIVE,RENAME TO t1;

SET SESSION wsrep_osu_method='RSU';
CREATE TABLE t1 (a MEDIUMINT UNSIGNED, b SMALLINT NOT NULL, KEY(b), PRIMARY KEY(a)) engine=innodb;
SET SESSION wsrep_osu_method=NBO;
DROP INDEX b ON t1;

SET SESSION wsrep_osu_method=RSU;
CREATE TABLE t0 (c0 INT);
SET SESSION wsrep_osu_method=NBO;
OPTIMIZE TABLE t0;