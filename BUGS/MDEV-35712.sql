SET SESSION collation_connection=utf8_german2_ci;

SET NAMES utf8mb3 COLLATE utf8mb3_unicode_520_ci;

select hex(string(_utf16 0xD800DC01 collate utf16_unicode_ci));
