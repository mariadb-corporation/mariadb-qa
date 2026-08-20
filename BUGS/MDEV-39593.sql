SELECT EXTRACTVALUE('<a/>', '/a[number()]');

SELECT EXTRACTVALUE ('<a/','/a[number()');

CREATE TABLE t1 (c INT);
LOCK TABLES t1 READ;
GRANT SELECT ON d.* TO u;
SELECT EXTRACTVALUE('','/a[number()]');
