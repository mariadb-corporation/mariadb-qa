CREATE FUNCTION json_array_add RETURNS STRING SONAME 'ha_connect.so';
SELECT json_array_add('[5,3,8,7,9]' a,4,9);
