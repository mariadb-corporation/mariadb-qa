# Requires standard m/s setup, use CLI on master to replay the SQL
RESET MASTER;
SET GLOBAL init_connect="foo";
CREATE TABLE t1 (c1 INT, c2 BINARY (25) NOT NULL, c3 SMALLINT(4) NULL, c4 BINARY (15) NOT NULL PRIMARY KEY, c5 SMALLINT NOT NULL UNIQUE KEY,c6 DEC(10,8) NOT NULL DEFAULT 3.141592) ENGINE=MyISAM;
CREATE TABLE t2 (a INT, b SMALLINT NOT NULL, c CHAR(12) NOT NULL, d VARCHAR(64) NOT NULL, e VARCHAR(89), f VARCHAR(5), g LONGBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=MyISAM;

# Requires standard m/s setup, use CLI on master to replay the SQL
SET sql_mode='';
GRANT PROXY ON dest TO''@'LOCALHOST';
RESET MASTER;
CREATE TABLE ti (a INT,b INT,c BINARY (0),d CHAR(0),e BINARY (0),f VARBINARY(0),g BLOB,h BLOB,id INT,KEY(b),KEY(e));#ERROR:0-Tabulka 'a' ji� existuje#ERRIN the ACTIVE state;
INSERT INTO ti VALUES (0,0,'DVHsOTsPKMesrQBFY0vq0qleFkABKfKxyuw0LJ','tqiFRYvdS0O0ntIiRY0mDbe0TtdV0','Jn0yJIDpy0asUAf0zbNqqgDYLcOxgKASrcIskmxlAe0vZGPFjtW0e0Nu0nq','pXx0cqQAkUlDpCPQCkqcuEbvKjUgg0v0zNJLzkabdA0jMgPDDd0TMzcauRQzD0xDlO0RVY0mygnngVcfThMPHoHSfn0YQX0OPWIIwPJWYztrPHtQ0CUwkTmZ0RxL0DoaVxiV0LDkhLXeTXvG0UgQPdWPCp0O0EDRZw0YKlI0kiBSk0QBMnDudWvD0px0xev0pnRrL0eUNRclAFXyDGMyRSqThbah0STdYfBciwWSwByMFr0wSufRgucVv',0,0,0);