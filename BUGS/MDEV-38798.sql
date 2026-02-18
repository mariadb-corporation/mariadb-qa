CREATE VIEW v AS select * from (select 'foo' AS a) sq;
CREATE PROCEDURE p() ALTER TABLE v TRUNCATE PARTITION p;
CALL p;
CALL p;
