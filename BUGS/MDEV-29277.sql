CREATE TABLE t2 (c INT);
DROP TABLE t,t2;
CREATE TABLE t2 (s CHAR(255),FULLTEXT (s)) DEFAULT CHARSET=utf8;
INSERT INTO t2 VALUES (10009);
SET GLOBAL innodb_trx_rseg_n_slots_debug=1,@@SESSION.pseudo_slave_mode=ON;
SHUTDOWN;
