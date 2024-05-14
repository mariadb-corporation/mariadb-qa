SET collation_connection='utf16_bin';
SELECT JSON_EXTRACT('{"a": 1,"b": 2}','$.a');

SET collation_connection=utf32_unicode_ci;
SELECT JSON_EXTRACT('[["A",2]]','$[0]');

SET collation_connection=ucs2_general_ci;
SELECT JSON_EXTRACT(JSON_COMPACT ('{"abc": "foo"}'),'$.abc');

SET character_set_database=ucs2;
SET CHARACTER SET cp1251_koi8;
SELECT JSON_EXTRACT('{ "\\"a\\"": 1}','$."\\"a\\""');
