DELIMITER $$
BEGIN NOT ATOMIC  DECLARE c INT DEFAULT sys.dbms_sql.open_cursor();  CALL sys.dbms_sql.parse(c, 'SHOW WARNINGS', 1);  SET c= sys.dbms_sql.execute(c);END;$$

PREPARE s FROM 'SHOW WARNINGS';
DELIMITER $$
BEGIN NOT ATOMIC  DECLARE c CURSOR FOR s;  OPEN c;END;$$
DELIMITER ;
