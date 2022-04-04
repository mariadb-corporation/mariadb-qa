SET sql_mode='';
CREATE TABLE t (d INT,b VARCHAR(1),c CHAR(1),g CHAR(1) GENERATED ALWAYS AS (SUBSTR(b,0,0)) VIRTUAL,PRIMARY KEY(b),KEY g(g)) ENGINE=InnoDB;
INSERT INTO t VALUES (0);
SET sql_mode='ORACLE';
INSERT INTO t SET c=REPEAT (1,0);
ALTER TABLE t CHANGE COLUMN a b INT;
DELETE FROM t;
SET sql_mode='';
SET GLOBAL table_open_cache=DEFAULT;
INSERT INTO t SET c='0';

SET sql_mode='';
CREATE TABLE t (a INT(1),d INT(1),b VARCHAR(1),c CHAR(1),vadc INT(1) GENERATED ALWAYS AS ( (a + length (d))) STORED,vbc CHAR(1) GENERATED ALWAYS AS (SUBSTR(b,0,0)) VIRTUAL,vbidxc CHAR(1) GENERATED ALWAYS AS (SUBSTR(b,0,0)) VIRTUAL,PRIMARY KEY(b (1),a,d),KEY d (d),KEY a (a),KEY c_renamed (c (1),b (1)),KEY b (b (1),c (1),a),KEY vbidxc (vbidxc),KEY a_2 (a,vbidxc),KEY vbidxc_2 (vbidxc,d)) DEFAULT CHARSET=latin1 ENGINE=InnoDB;
INSERT INTO t VALUES (0,0,1,0,1,0,1,0,0);
SET SESSION sql_mode='ORACLE';
INSERT INTO t SET c=REPEAT (1,0);
ALTER TABLE t CHANGE COLUMN a b CHAR(1);
DELETE FROM t;
SET SESSION sql_mode='DEFAULT';

# mysqld options required for replay:  --sql_mode=
CREATE TABLE t (a INT(1),d INT(1),b VARCHAR(1),c CHAR(1),vadc INT(1) GENERATED ALWAYS AS ( (a + length (d))) STORED,vbc CHAR(1) GENERATED ALWAYS AS (SUBSTR(b,0,0)) VIRTUAL,vbidxc CHAR(1) GENERATED ALWAYS AS (SUBSTR(b,0,0)) VIRTUAL,PRIMARY KEY(b (1),a,d),KEY d (d),KEY a (a),KEY c_renamed (c (1),b (1)),KEY b (b (1),c (1),a),KEY vbidxc (vbidxc),KEY a_2 (a,vbidxc),KEY vbidxc_2 (vbidxc,d)) DEFAULT CHARSET=latin1;
INSERT INTO t VALUES (0,0,1,0,1,0,1,0,0);
SET SESSION sql_mode= ORACLE;  
INSERT INTO t SET c=REPEAT (1,0);
ALTER TABLE t CHANGE COLUMN a b CHAR(1);
DELETE FROM t;
SET SESSION sql_mode= DEFAULT; 
SET GLOBAL table_open_cache=DEFAULT;
INSERT INTO t SET c=CONCAT (REPEAT (1,0),1,1);

SET sql_mode='';
CREATE TABLE t (a INT(1),d INT(1),b VARCHAR(1),c CHAR(1),vadc INT(1) GENERATED ALWAYS AS ( (a + length (d))) STORED,vbc CHAR(1) GENERATED ALWAYS AS (SUBSTR(b,0,0)) VIRTUAL,vbidxc CHAR(1) GENERATED ALWAYS AS (SUBSTR(b,0,0)) VIRTUAL,PRIMARY KEY(b (1),a,d),KEY d (d),KEY a (a),KEY c_renamed (c (1),b (1)),KEY b (b (1),c (1),a),KEY vbidxc (vbidxc),KEY a_2 (a,vbidxc),KEY vbidxc_2 (vbidxc,d)) DEFAULT CHARSET=latin1;
INSERT INTO t VALUES (0,0,1,0,1,0,1,0,0);
SET SESSION sql_mode=ORACLE;
INSERT INTO t SET c=REPEAT (1,0);
ALTER TABLE t CHANGE COLUMN a b CHAR(1);
DELETE FROM t;
SET SESSION sql_mode=DEFAULT;
SET GLOBAL table_open_cache=DEFAULT;
INSERT INTO t SET c=CONCAT (REPEAT (1,0),1,1);
