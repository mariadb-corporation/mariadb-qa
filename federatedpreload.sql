INSTALL SONAME 'ha_federatedx.so';
CREATE USER federatedx@localhost IDENTIFIED BY 'PWD';
GRANT ALL ON test.* TO federatedx@localhost;
FLUSH PRIVILEGES;
CREATE SERVER srv FOREIGN DATA wrapper mysql options (socket '../socket.sock', DATABASE 'test', USER 'federatedx', PASSWORD 'PWD');
CREATE TABLE t2 (c1 INT PRIMARY KEY,c2 BLOB, c3 TEXT) ENGINE=InnoDB;
INSERT INTO t2 VALUES (0,NULL,'a');
CREATE TABLE t1 CONNECTION='srv/t2' ENGINE=FEDERATED;
SELECT * FROM t1;
