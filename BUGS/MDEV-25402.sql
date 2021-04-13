SET @c:="SET SESSION collation_connection=utf32_spanish_ci";
PREPARE s FROM @c;
EXECUTE s;
CREATE PROCEDURE p (IN i INT) EXECUTE s;
SET SESSION character_set_connection=latin2;
SET @c:="SET @b=get_format(DATE,'EUR')";
PREPARE s FROM @c;
EXECUTE s;
CALL p (@a);
