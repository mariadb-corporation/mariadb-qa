INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
CREATE SERVER s FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER 'Spider',PASSWORD 'PWD123');
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE ts (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "s",TABLE "t"';
DELIMITER $$
CREATE PROCEDURE sp() BEGIN
DECLARE v1 DATE; SELECT c FROM ts;
WHILE EXISTS (SELECT 1 FROM ts WHERE c>v1 AND c<=v1) DO SELECT st.c; END WHILE;
WHILE EXISTS (SELECT 1 FROM ts WHERE c<v1 AND EXISTS (SELECT 1 FROM t WHERE ts.c=t.c)) DO SELECT ts.c; DELETE ts FROM ts; END WHILE; 
END $$
DELIMITER ;
CALL sp();

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
CREATE SERVER s FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER 'Spider',PASSWORD 'PWD123');
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE ts (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "s",TABLE "t"';
DELIMITER $$
CREATE PROCEDURE sp() BEGIN
DECLARE v1 DATE; SELECT c FROM ts;
WHILE EXISTS (SELECT 1 FROM ts WHERE c>v1) DO SELECT st.c; END WHILE;
WHILE EXISTS (SELECT 1 FROM ts WHERE c<v1 AND EXISTS (SELECT 1 FROM t WHERE ts.c=t.c)) DO SELECT ts.c; DELETE ts FROM ts; END WHILE; 
END $$
DELIMITER ;
CALL sp();

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
CREATE SERVER s FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER 'Spider',PASSWORD 'PWD123');
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE ts (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "s",TABLE "t"';
DELIMITER $$
CREATE PROCEDURE sp() BEGIN
DECLARE v1 INT; SELECT c FROM ts;
WHILE EXISTS (SELECT 1 FROM ts WHERE c>v1 AND c<=v1) DO SELECT st.c; END WHILE;
WHILE EXISTS (SELECT 1 FROM ts WHERE c<v1 AND EXISTS (SELECT 1 FROM t WHERE ts.c=t.c)) DO SELECT ts.c; DELETE ts FROM ts; END WHILE; 
END $$
DELIMITER ;
CALL sp();


INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS(SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t(c INT,c2 CHAR,c3 DATE) ENGINE=InnoDB;
CREATE TABLE st(c INT,c2 CHAR,c3 DATE,c4 CHAR) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
DELIMITER $$
CREATE PROCEDURE sp() BEGIN
DECLARE v1 DATE;
SELECT c,c2,c3 FROM st;
WHILE EXISTS(SELECT 1 FROM st WHERE c3>v1 AND c3<=v1 AND NOT EXISTS(SELECT * FROM t a WHERE a.c=st.c)) DO SELECT st.c,st.c2,st.c3; END WHILE;
WHILE EXISTS(SELECT 1 FROM st WHERE c3<v1 AND EXISTS(SELECT * FROM t a WHERE st.c=a.c)) DO SELECT st.c; DELETE st FROM st; END WHILE;
END $$
DELIMITER ;
CALL sp();

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t1 (c1 INT,c2 CHAR) ENGINE=InnoDB;
CREATE TABLE t2 (c1 INT,c2 CHAR,c3 DATE) ENGINE=InnoDB;
CREATE TABLE ts (c1 INT,c3 DATE) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t2"';
INSERT INTO t2 VALUES (0,'a',0);
DELIMITER $$
CREATE PROCEDURE sp() BEGIN
DECLARE v1 DATE; 
SELECT MAX(c3) INTO v1 FROM ts a;
WHILE EXISTS(SELECT * FROM ts WHERE c3=1 AND NOT EXISTS (SELECT 1 FROM t1 WHERE t1.c2=ts.c3)) DO SELECT 1; END WHILE;
END $$
DELIMITER ;
CALL sp();