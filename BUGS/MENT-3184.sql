DELIMITER $$
BEGIN NOT ATOMIC  DECLARE c INT DEFAULT sys.dbms_sql.open_cursor();  CALL sys.dbms_sql.parse(c, 'DROP PACKAGE BODY sys.dbms_sql', 1);END;$$
DELIMITER ;
