# mysqld options required for replay:  --skip-grant-tables=1
CREATE DEFINER=a PROCEDURE p() SELECT 1;

# mysqld options required for replay:  --skip-grant-tables=1
CREATE DEFINER=a PROCEDURE p (INOUT i INT) CONTAINS SQL SET GLOBAL optimizer_switch=0;
