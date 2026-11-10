SET sql_mode=ORACLE;
CREATE TABLE t1 (y INT);
DELIMITER $$
DECLARE c INT; n INT; BEGIN   c:= sys.dbms_sql.open_cursor(); sys.dbms_sql.parse(c, 'INSERT INTO t1 WITH c AS (SELECT :a v) SELECT d.v FROM c, c d', 1);  sys.dbms_sql.bind_variable(c, 'a', 5);  n:= sys.dbms_sql.execute(c); END;$$
DELIMITER ;
SELECT * FROM t1;
