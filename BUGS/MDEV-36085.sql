SET @@collation_connection=utf32_czech_ci;
SELECT''LIKE''ESCAPE EXPORT_SET (1,1,1,1,'');

SET collation_connection='ucs2_bin';
SELECT''LIKE''ESCAPE EXPORT_SET (1,1,1,1,'');

SET NAMES utf8,collation_connection='utf16le_bin';
SELECT''LIKE''ESCAPE EXPORT_SET (1,1,1,1,'');

SET collation_connection='ucs2_bin';
SELECT 0 LIKE 0 ESCAPE EXPORT_SET (1,1,1,1,0);
