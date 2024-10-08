CREATE OR REPLACE TABLE t1 (a INT);
ALTER TABLE t1 ADD row_start TIMESTAMP(6) AS ROW START, ADD row_end TIMESTAMP(6) AS ROW END, ADD PERIOD FOR SYSTEM_TIME(row_start,row_end), WITH SYSTEM VERSIONING, MODIFY row_end VARCHAR(8);

CREATE TEMPORARY TABLE t1 (i INT KEY, c CHAR(10)) ENGINE=MEMORY ROW_FORMAT=DYNAMIC;
CREATE TABLE t1 (a INT, b INT, KEY(a), INDEX b (b));
DROP TABLE t1;
ALTER TABLE t1 ADD ROW_START TIMESTAMP (6) AS ROW START, ADD ROW_END TIMESTAMP (6) AS ROW END, ADD PERIOD FOR SYSTEM_TIME(ROW_START,ROW_END), WITH SYSTEM VERSIONING, MODIFY ROW_END VARCHAR(8);
