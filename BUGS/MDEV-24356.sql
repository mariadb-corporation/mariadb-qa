CREATE DATABASE `db_new..............................................end`;
SET SESSION foreign_key_checks=0;
USE `db_new..............................................end`;
CREATE TABLE mytable_ref (id int,constraint FOREIGN KEY (id) REFERENCES FOO(id) ON DELETE CASCADE) ;
SELECT constraint_catalog, constraint_schema, constraint_name, table_catalog, table_schema, table_name, column_name FROM information_schema.key_column_usage WHERE (constraint_catalog IS NOT NULL OR table_catalog IS NOT NULL) AND table_name != 'abcdefghijklmnopqrstuvwxyz' ORDER BY constraint_name, table_name, column_name;

CREATE DATABASE `..................................................`;
USE `..................................................`;
CREATE TABLE t(a INT KEY,b INT,FOREIGN KEY (b)REFERENCES t (a)) ROW_FORMAT=REDUNDANT;
INSERT INTO t VALUES(6,6,6);

create database `db_new..............................................end`;
set foreign_key_checks=0;
USE `db_new..............................................end`;
CREATE TABLE t0(a INT,b CHAR,FOREIGN KEY (a)REFERENCES t_0(a) ON DELETE CASCADE);
SELECT * FROM information_schema.table_constraints;
