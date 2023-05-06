SET collation_connection= utf32_unicode_520_ci;
SELECT CEIL(@f := (TIMESTAMP('2012-12-12 00:00:00.0000')) / 1);

CREATE TABLE t (i MEDIUMINT(60));
INSERT INTO t VALUES (5);
SELECT floor(sum(avg(i)) OVER ()) FROM t;

CREATE TABLE t (c DECIMAL(65,10));
SET SESSION div_precision_increment=65550;
SELECT CEILING (AVG(c)) FROM t;
