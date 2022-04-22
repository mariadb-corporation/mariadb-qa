SET @a='-9223372036854775808';  # Quite specific value; considerably varying it will not work
CREATE TABLE t (c1 INT,c2 CHAR) ENGINE=InnoDB;
SELECT SUBSTR(0,@a) FROM t;
