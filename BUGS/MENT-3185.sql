SET sql_mode=ORACLE;
DELIMITER $$
CREATE PROCEDURE p1 AS BEGIN NULL; END;$$
CREATE PROCEDURE p2 AS r sys.dbms_sql.desc_rec; d sys.dbms_sql.desc_tab; c INT;
BEGIN  r.col_name:= 'x';  d(1):= r;  c:= sys.dbms_sql.open_cursor();  CALL sys.dbms_sql.parse(c, 'DO 1', 1);  SELECT d(1).col_name;END;$$
CREATE PROCEDURE p3 AS c INT;BEGIN   c:= sys.dbms_sql.open_cursor();  sys.dbms_sql.parse(c, 'DROP PROCEDURE p1', 1);  p2();END;$$
DELIMITER ;
CALL p3();
CALL p2();
