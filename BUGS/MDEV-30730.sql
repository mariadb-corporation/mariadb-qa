SET collation_server=utf8mb4_unicode_ci;
SET GLOBAL wsrep_mode=disallow_local_gtid;
SET SESSION wsrep_on=0;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (c DATE,d DATE NOT NULL,cd TEXT AS (CONCAT (c,IF(c=d,DATE_FORMAT(d,''),''))));
INSERT INTO t (c) VALUES (1);
INSERT INTO t (c) VALUES (1);
