# mysqld options required for replay: --log-bin
CREATE TABLE t1 (a tinyBLOB) ENGINE=InnoDB;
SET SESSION pseudo_slave_mode=ON;
SET default_storage_engine=InnoDB,default_storage_engine='HEAP',GLOBAL default_storage_engine='MERGE';
XA START 'a';
INSERT INTO t1 VALUES (1);
XA END 'a';
XA PREPARE 'a';
ALTER TABLE t1 ENGINE=MERGE UNION (t_not_exists,t2);
DROP TABLE t1;
CREATE TABLE t1 (c1 SMALLINT,c2 INT,c3 BINARY (1));
ALTER TABLE t1 ENGINE=InnoDB;

SET SESSION pseudo_slave_mode=ON;
CREATE TABLE t1 (c VARCHAR(30) CHARACTER SET utf8, UNIQUE (c (10))) ENGINE=InnoDB;
SET default_storage_engine=InnoDB, default_storage_engine='HEAP', GLOBAL default_storage_engine='MERGE';
XA START 'a';
INSERT INTO t1 VALUES (23594);
XA END 'a';
XA PREPARE 'a';
ALTER TABLE t1 ENGINE=MERGE UNION (t_not_exists, t2);
DROP TABLE t1;
CREATE TABLE t1 (b1 CHAR(2), b2 CHAR(2), b3 CHAR(1), b4 CHAR(1));
ALTER TABLE t1 ENGINE=InnoDB;

INSTALL SONAME 'ha_mroonga';
CREATE TABLE t (id INT KEY,user_id INT,title CHAR,KEY(user_id)) DEFAULT CHARSET=UTF8;
ALTER TABLE t ENGINE=mroonga COMMENT='ENGINE "InnoDB"';
