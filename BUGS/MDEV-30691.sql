SET @@collation_connection=utf32_czech_ci;
SET @arr=CONCAT_WS('','[',REPEAT ('1234567,',1250000/2),'2345678]');
SELECT JSON_DETAILED (@arr);
