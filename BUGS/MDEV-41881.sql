# mysqld options required for replay:  --performance-schema=ON
SET sql_mode=ORACLE;
DELIMITER $$ 
DECLARE TYPE t IS TABLE OF INT INDEX BY INTEGER; a t; BEGIN BEGIN DO a(1); EXCEPTION WHEN OTHERS THEN NULL; END; SELECT 1; END$$
