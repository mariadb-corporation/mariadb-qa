SELECT JSON_CONTAINS('{"a":[]}',CONCAT('{"a":',REPEAT('[',683),REPEAT(']',683),'}'));
