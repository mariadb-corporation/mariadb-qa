CREATE TABLE t (f SET(''));
INSERT INTO t VALUES (111111111111111111111);

CREATE TABLE t (f SET('')) ENGINE=MyISAM;
INSERT INTO t VALUES (111111111111111111111);

CREATE TABLE t (c SET('') KEY,c2 BLOB,c3 BLOB);
INSERT INTO t VALUES (1.e+20,0,0e+1);
