set sql_mode='';
CREATE ROLE i0;
DELETE FROM mysql.user;
GRANT USAGE ON *.* TO i0;
DROP ROLE i0;
SHOW GRANTS;
