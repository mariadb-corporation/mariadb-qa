CREATE SEQUENCE s AS BIGINT UNSIGNED START WITH 9223372036854775800 INCREMENT 0;
SET GLOBAL AUTO_INCREMENT_INCREMENT=10;
SELECT NEXTVAL (s);
FLUSH TABLES WITH READ LOCK;
UPDATE s SET a=1;

CREATE SEQUENCE s AS BIGINT UNSIGNED START WITH 9223372036854775800 INCREMENT 0;
SET GLOBAL AUTO_INCREMENT_INCREMENT=100;
SELECT SETVAL (s,12345678901234567890);
