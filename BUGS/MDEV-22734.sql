USE test;
SET time_zone="-02:00";
CREATE TABLE t(c TIMESTAMP KEY);
SELECT * FROM t WHERE c='2010-00-01 00:00:00';
