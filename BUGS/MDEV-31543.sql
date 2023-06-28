SET @arr1='[1,2,3]';
SET character_set_database=ucs2;
SET CHARACTER SET utf8;
SET @obj1='{ "a": 1,"b": 2,"c": 3}';
SELECT JSON_OBJECT_FILTER_KEYS (@obj1,@arr1);
