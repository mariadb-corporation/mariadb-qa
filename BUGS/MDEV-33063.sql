ALTER TABLE mysql.gtid_slave_pos CHANGE seq_no seq_no CHAR(4);
CREATE TABLE t (c FLOAT,c2 FLOAT);
INSERT INTO t VALUES (0,0),(DEFAULT,DEFAULT);
CREATE SEQUENCE s START WITH 9223372036854775805 MINVALUE 9223372036854775804 MAXVALUE 9223372036854775806 CACHE 1 cycle;
