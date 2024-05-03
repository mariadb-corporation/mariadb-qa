CREATE VIEW c AS SELECT * FROM information_schema.tables ORDER BY table_name  COLLATE UTF8_general_ci;
CREATE TABLE t (a CHAR(1) KEY) ;
DELETE FROM t USING c,t;
