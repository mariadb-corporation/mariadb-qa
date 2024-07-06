# mysqld options required for replay:  --skip-grant-tables=1
CREATE DEFINER=a PROCEDURE p() SELECT 1;
