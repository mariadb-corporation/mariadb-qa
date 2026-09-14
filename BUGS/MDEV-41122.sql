SET sql_mode='';
CREATE ROLE r1;
DELETE FROM mysql.user WHERE user='r1';
GRANT SELECT ON *.* TO r1;
DROP ROLE r2,r1;
GRANT r1 TO u1;
