# mysqld options required for replay:  --log-bin
CREATE TABLE t (c INT KEY);
XA START 'a';
INSERT INTO t VALUES (1);
XA END 'a';
XA PREPARE 'a';
LOAD INDEX INTO CACHE c KEY(PRIMARY);

# mysqld options required for replay:  --log-bin
CREATE TABLE t (a INT);
XA START 'a';
INSERT INTO t VALUES (1);
XA END 'a';
XA PREPARE 'a';
XA START 'a';
LOAD INDEX INTO CACHE t IGNORE LEAVES;

# mysqld options required for replay:  --log-bin
CREATE TABLE t1 (c INT);
ALTER TABLE t1 ADD c2 BLOB;
XA START 'a';
INSERT INTO t1 VALUES(0,0);
XA END 'a';
XA PREPARE 'a';
LOAD INDEX INTO CACHE t1 INDEX (`PRIMARY`);
