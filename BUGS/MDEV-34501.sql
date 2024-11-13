# mysqld options required for replay:  --skip-grant-tables=1
CREATE DEFINER=a PROCEDURE p() SELECT 1;

# mysqld options required for replay:  --skip-grant-tables=1
CREATE DEFINER=a PROCEDURE p (INOUT i INT) CONTAINS SQL SET GLOBAL optimizer_switch=0;

# mysqld options required for replay:  --skip-grant-tables=1
CREATE DEFINER=USER1 PROCEDURE p (OUT i1 NUMERIC,INOUT i2 NUMERIC(0,0)) SQL SECURITY INVOKER XA ROLLBACK'';
