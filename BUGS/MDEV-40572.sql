SET collation_connection=ucs2_general_ci;
SELECT JSON_OVERLAPS ('{"B":{}}', '{"B":{') AS exp;

SET character_set_connection=utf16;
SELECT JSON_OVERLAPS ('{"B":{}}', '{"B":{') AS exp;
