SET SQL_MODE='';
SET SESSION enforce_storage_engine=Aria;
CREATE TABLE t (c INT,c2 CHAR(1) NOT NULL);
SET @@optimizer_where_cost=1;
SET big_tables=1;
SET @@in_predicate_conversion_threshold=2;
INSERT INTO t (c) VALUES (1);
SELECT * FROM t WHERE c2 IN ('','');

SET sql_mode='',optimizer_where_cost=1,big_tables=1,in_predicate_conversion_threshold=2;
CREATE TABLE t (c CHAR(1) NULL);
INSERT INTO t (c) VALUES (1);
SELECT * FROM t WHERE c IN ('','');

SET optimizer_where_cost=1,big_tables=1,in_predicate_conversion_threshold=2;
CREATE TABLE t (c CHAR(1) NULL) ENGINE=Aria;
INSERT INTO t (c) VALUES (1);
SELECT * FROM t WHERE c IN ('','');

SET optimizer_where_cost=1,big_tables=1,in_predicate_conversion_threshold=2;
CREATE TABLE t (c CHAR(1) NULL) ENGINE=MyISAM;
INSERT INTO t (c) VALUES (1);
SELECT * FROM t WHERE c IN ('','');
