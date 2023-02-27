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

SET @@sql_mode='real_as_float,pipes_as_concat,ansi_quotes,IGNORE_space,IGNORE_bad_table_options,only_full_group_by,no_unsigned_subtraction,no_dir_in_create,POSTGRESQL,ORACLE,MSSQL,DB2,MAXDB,no_key_options,no_table_options,no_field_options,MYSQL323,MYSQL40,ANSI,no_auto_value_on_zero,no_backslash_escapes,strict_trans_tables,strict_all_tables,no_zero_in_date,no_zero_date,allow_invalid_dates,error_for_division_by_zero,TRADITIONAL,no_auto_create_user,high_not_precedence,no_engine_substitution,pad_char_to_full_length,simultaneous_assignment';
SET collation_connection=ucs2_general_ci;
SELECT CONCAT (0,JSON_VALUE ('"1"','$'));

SET @json='{ "A": [ [{"k":"v"},[15]], true], "B": {"C": 1} }'; 
SELECT JSON_VALUE(@json, '$.A[last-1][last-1].key1'); 

SET collation_connection=eucjpms_bin;
SET @json='{ "A": [ [{"k":"v"},[1]],true],"B": {"C": 1} }';
SELECT JSON_VALUE(@json,'$.A[last-1][last-1].key1');

SET @json='{ "A": [ [{"k":"v"},[1]],true],"B": {"C": 1} }';
SELECT JSON_VALUE(@json,'$.A[last-1][last-1].key1');

SET @json='{ "A": [ [{"k":"v"},[1]],true],"B": {"C": 1} }';
SET collation_connection='ucs2_bin';
SELECT JSON_VALUE(@json,'$.A[last-1][last-1].key1');

SET @json='{ "A": [ [{"k":"v"},[15]],true],"B": {"C": 1} }';
SET sql_mode=0,character_set_connection=utf32;
SELECT JSON_VALUE(@json,'$.A[last-1][last-1].key1');

SET @json='{ "A": [ [{"k":"v"},[15]],true],"B": {"C": 1} }';
SET collation_connection='tis620_bin';
SELECT JSON_VALUE(@json,'$.A[last-1][last-1].key1');
