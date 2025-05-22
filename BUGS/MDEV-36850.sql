CREATE TABLE t1 (a INT);
SET character_set_database=sjis;
SET collation_connection=ucs2_general_ci;
SET sql_mode=ORACLE;
DELIMITER $$
DECLARE
  TYPE first_names_t IS TABLE OF VARCHAR2(64) INDEX BY VARCHAR2(20);
  first_names first_names_t;
  nick VARCHAR(64):= 'Monty';
BEGIN
  first_names('Monty') := 'Michael';
  INSERT INTO t1 VALUES (first_names(nick));
  INSERT INTO t1 VALUES (first_names(TRIM(nick || ' ')));
END;
$$
DELIMITER ;
