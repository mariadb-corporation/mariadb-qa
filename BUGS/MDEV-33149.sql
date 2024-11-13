SELECT json_array_intersect(@json1,@json2);

SELECT JSON_OBJECT_FILTER_KEYS (@obj1,JSON_ARRAY_INTERSECT (JSON_KEYS (@obj1),JSON_KEYS (@obj2)));
