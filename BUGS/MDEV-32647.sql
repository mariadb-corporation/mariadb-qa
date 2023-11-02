SET sql_mode='';
CREATE TABLE t (a varchar(10),b CHAR(20));
INSERT INTO t VALUES ('Laptop',COLUMN_CREATE ('color','black','price',500));
SELECT a,COLUMN_GET (b,'color' AS CHAR) AS color FROM t;

SET sql_mode='';
CREATE TABLE t (a CHAR(20),b CHAR(20));
INSERT INTO t VALUES ('Laptop',COLUMN_CREATE ('color','black','price',0));
SELECT a,column_list (b) FROM t;

SET sql_mode='';
CREATE TABLE t (a varchar(10),b CHAR(20));
INSERT INTO t VALUES ('Shirt',COLUMN_CREATE ('color','blue','size',0));
UPDATE t SET b=COLUMN_DELETE(b,'price') WHERE COLUMN_GET (b,'color' AS char)='blue';
