SET GLOBAL query_cache_type=1;
SET SESSION query_cache_type=ON;
CREATE TABLE t (c INT) ENGINE=InnoDB;
XA START 'a';
SELECT * FROM t;
XA END 'a';
XA PREPARE 'a';
SELECT * FROM t;


SET GLOBAL query_cache_type=ON;
SET query_cache_type=ON;
CREATE TABLE t1 (c INT)Engine=Innodb;
XA START 'a';
SELECT * FROM t1;
XA END 'a';
XA PREPARE 'a';
SELECT * FROM t1;
