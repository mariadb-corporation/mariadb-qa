SET COLLATION_CONNECTION= ucs2_unicode_ci;
SELECT JSON_VALUE('["foo"]', '$**[0]') AS f;

SET collation_connection='ucs2_bin';
SELECT json_value ('[{"foo": 1},"bar"]','$[*][0]');

SET NAMES utf8,collation_connection=utf16le_general_ci;
SELECT JSON_VALUE ('"1"','$')+1.0e0;
