# mysqld options required for replay: --sql_mode=ONLY_FULL_GROUP_BY 
SET GLOBAL aria_encrypt_tables=ON;
CREATE TABLE t (a INT KEY,b INT,KEY(b)) ENGINE=Aria;
INSERT INTO t (a) VALUES (1);
ALTER TABLE t CHANGE COLUMN b c CHAR(0);
LOAD INDEX INTO CACHE t IGNORE LEAVES;
SHUTDOWN;
