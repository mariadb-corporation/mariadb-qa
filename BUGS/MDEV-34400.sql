CREATE FUNCTION json_array_add RETURNS STRING SONAME 'ha_connect.so';
SELECT json_array_add('[5,3,8,7,9]' a,4,9);

CREATE FUNCTION json_array_add RETURNS STRING SONAME 'ha_connect.so';
SET character_set_connection=ucs2;
SELECT json_array_add ('a' json_,'b');
