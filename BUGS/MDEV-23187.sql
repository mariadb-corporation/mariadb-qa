SET COLLATION_CONNECTION= ucs2_unicode_ci;
SELECT JSON_VALUE('["foo"]', '$**[0]') AS f;

SET collation_connection='ucs2_bin';
SELECT json_value ('[{"foo": 1},"bar"]','$[*][0]');

SET NAMES utf8,collation_connection=utf16le_general_ci;
SELECT JSON_VALUE ('"1"','$')+1.0e0;

SET character_set_connection=utf16;
SELECT CONCAT (0,JSON_VALUE ('"1"','$'));

SET character_set_connection=utf32;
SELECT JSON_VALUE ('"123"','$') DIV 2;

SET collation_connection='utf32_unicode_ci';
SELECT CAST(JSON_VALUE ('"1234"','$') AS UNSIGNED);
