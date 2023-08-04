SET @@collation_connection=utf32_czech_ci;
SET @arr=CONCAT_WS('','[',REPEAT ('1234567,',1250000/2),'2345678]');
SELECT JSON_DETAILED (@arr);

SET character_set_database=ucs2;
SET CHARACTER SET DEFAULT;
SET @json2='[[1,2,3],[4,5,6],[1,3,2]]';
SET @json1='[[1,2,3],[4,5,6],[1,3,2]]';
SELECT JSON_ARRAY_INTERSECT (@json1,@json2);

SET collation_connection='utf16le_general_ci';
SELECT JSON_KEY_VALUE('{"key1":"val1"}', '$');
