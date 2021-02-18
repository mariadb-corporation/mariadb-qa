SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (c INT(1)UNSIGNED AUTO_INCREMENT PRIMARY KEY,c2 CHAR(1)) ENGINE=InnoDB;
XA START 'a';
DELETE FROM t;
INSERT INTO t VALUES(0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (1,1);
INSERT INTO t VALUES(0,0), (0,0), (0,0), (0,0);

# Original testcase
SET sql_mode='';
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (id INT(1)UNSIGNED AUTO_INCREMENT,fname CHAR(1),PRIMARY KEY(id)) DEFAULT CHARSET=latin1;
XA START 'xa_disconnect';
DELETE FROM t;
INSERT INTO t VALUES('',''), ('',''), ('',''), ('',''), ('',''), ('',''), ('-838:59:59','-838:59:59'), ('',''), ('',''), ('',''), ('00 00:00:04','00 00:00:04'), ('04 04:04:04','04 04:04:04'), ('34 22:59:57','34 22:59:57'), ('00 00:04','00 00:04'), ('05 05:05','05 05:05'), ('34 22:56','34 22:56'), ('05 05','05 05'), ('06 06','06 06'), ('34 22','34 22'), ('',''), ('','');
INSERT INTO t VALUES(0,'val8');
INSERT INTO t VALUES(0,'');
INSERT INTO t VALUES(0,1), (0,1), (0,1), (0,1);
