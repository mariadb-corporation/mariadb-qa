SET NAMES utf8,character_set_connection=utf32;
SELECT JSON_KEYS ('{"S":-1.0,"D": {"o":,"a": }}');

SET SESSION collation_connection=utf32_croatian_ci;
SELECT JSON_KEYS (JSON_OBJECT (0,3));
