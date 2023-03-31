SET @schema_obj='{ "type": "object","properties": { "number1":{"type":"number"},"string1":{"type":"string"},"array1":{"type":"array"} },"dependentRequired": { "number1":["string1"] } }';
SET NAMES utf8,collation_connection=utf32_bin;
SELECT JSON_SCHEMA_VALID (@schema_obj,'{"array1":[1,2,3],"number1":2,"string1":"abc"}');
