CREATE TABLE tab (c INT KEY,c2 POINT,c3 LINESTRING,c4 POLYGON,c5 GEOMETRY);
ALTER TABLE mysql.column_stats RENAME TO mysql.column_stats1;
CREATE TABLE t (a INT,b CHAR(1),c FLOAT);
ALTER TABLE t RENAME mysql.column_stats;
ALTER TABLE tab CHANGE COLUMN c3 c33 LINESTRING;

CREATE TABLE t1 (f1 VARCHAR(1)) ENGINE=InnoDB;
ALTER TABLE t1 ADD KEY2 INT, ADD KEY(KEY2);
ALTER TABLE t1 RENAME t3;
ALTER TABLE mysql.column_stats RENAME TO mysql.column_stats1;
ALTER TABLE t3 RENAME mysql.column_stats;
ALTER TABLE mysql.db DROP COLUMN delete_history_priv;

ALTER TABLE mysql.column_stats RENAME TO mysql.column_stats0;
CREATE TABLE t0 (a INT KEY);
ALTER TABLE t0 RENAME mysql.column_stats;
CREATE TABLE t (c INT,d INT);
ALTER TABLE t DROP b,DROP c,DROP d,ADD COLUMN (b INT,c CHAR,d INT);

CREATE TABLE t (c FLOAT);
ALTER TABLE mysql.column_stats RENAME TO mysql.column_stats1;
CREATE TABLE t2 (a CHAR(20) BINARY);
ALTER TABLE t RENAME mysql.column_stats;
ALTER TABLE t2 CHANGE COLUMN a a CHAR(43);

DROP TABLE IF EXISTS mysql.column_stats;
CREATE TABLE t (a INT,b INT,KEY(a));
ALTER TABLE t RENAME mysql.column_stats;
ALTER TABLE mysql.slow_log DROP COLUMN thread_id;
