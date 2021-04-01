SET SQL_MODE='';
SET @cmd="ALTER TABLE non.existing ENGINE=NDB";
PREPARE stmt FROM @cmd;
EXECUTE stmt;
EXECUTE stmt;

SET sql_mode='';
CREATE PROCEDURE p1 (IN i INT) ALTER TABLE t ENGINE=none;
CALL p1 (1);
CALL p1 (1);
