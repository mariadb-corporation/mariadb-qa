CREATE USER user@localhost;
SELECT authentication_string <> '' FROM mysql.user;

SET SESSION sql_buffer_result=ON;
SELECT authentication_string <>''FROM mysql.user;
