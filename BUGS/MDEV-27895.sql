# mysqld options required for replay:  --performance-schema
INSERT INTO performance_schema.setup_actors VALUES ('%','USR','%');
SET SESSION sql_mode='pad_char_to_full_length';
SET CHARACTER SET 'BINARY';
SET collation_connection=ucs2_general_ci;
INSERT INTO performance_schema.setup_actors SET USER='a',HOST='LOCALHOST';
