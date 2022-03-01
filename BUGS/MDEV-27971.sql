# mysqld options required for replay: --log-bin 
CREATE TABLE t (i INT KEY,a GEOMETRY NOT NULL,b GEOMETRY NOT NULL,c INT,SPATIAL INDEX (a),KEY(a),KEY(b)) ENGINE=InnoDB;
SET unique_checks=0, foreign_key_checks=0;
CREATE TABLE t2 (d INT UNSIGNED NOT NULL,e CHAR NOT NULL DEFAULT'',PRIMARY KEY(d)) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t2 VALUES (1,2),(1,3);
SELECT * FROM t;
INSERT INTO t2 VALUES (1,''),(3,''),(5,'');
