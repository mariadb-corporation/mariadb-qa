SET sql_mode=ORACLE;
DELIMITER $$
CREATE PROCEDURE p(x IN INT) AS BEGIN NULL; END;
$$
DECLARE c INT; n INT;
BEGIN  c:= sys.dbms_sql.open_cursor();  sys.dbms_sql.parse(c, 'CALL p(:a)', 1);  sys.dbms_sql.bind_variable(c, 'a', 1); n:= sys.dbms_sql.execute(c);END; $$
DELIMITER ;
