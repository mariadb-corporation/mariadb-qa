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

SET character_set_connection=utf32;
SELECT JSON_OBJECT_TO_ARRAY ('{"q": 1}');

SET collation_connection=ucs2_bin;
SET @JSON='{ "A": [0,[1,2,3],[4,5,6],"seven",8,true,false,"eleven",[1,[1,1],{"KEY1":"VALUE1"},[1]],true],"B": {"C": 1},"D": 2 }';
SELECT JSON_DETAILED (@JSON);
