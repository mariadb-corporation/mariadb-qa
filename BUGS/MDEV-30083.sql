SET GLOBAL table_open_cache=1;
INSTALL SONAME 'ha_federatedx.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'federatedx',PASSWORD'');
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
CREATE TABLE t CONNECTION='srv/t2' ENGINE=FEDERATED;
RENAME TABLE t TO t3;  # Likely point where the wrong situation is created
CREATE TABLE t (s INT) ENGINE=InnoDB;
XA START 0x1;
INSERT INTO t VALUES (9);
SELECT * FROM mysql.roles_mapping;
INSERT INTO t3 VALUES();
UPDATE t2 SET d=0;
SELECT * FROM mysql.roles_mapping;
SELECT fn1 (1e);
HANDLER t OPEN;
INSERT INTO t SELECT * FROM t;
DELETE FROM mysql.tables_priv;
SAVEPOINT s;
