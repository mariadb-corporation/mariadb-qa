# mysqld options required for replay:  --gtid_strict_mode=1
RESET MASTER;
CREATE TABLE t1 ( index1 smallint(6) default NULL,nr smallint(6) default NULL,KEY index1(index1) ) ENGINE=InnoDB;#ERROR: 1399 - XAER_RMFAIL: The command cannot be executed when global transaction is in the  ACTIVE state#ERROR: 1099 - Table 'a' was locked with a READ lock and can't be updated;
SET gtid_seq_no=200;
ANALYZE TABLE gis_multi_linestring;
