SELECT 1 = ALL ( SELECT 1 a union SELECT 1 ORDER BY sum(a) OVER ( ) ) ;

SELECT 5 IN ( SELECT 10 union SELECT 20 ORDER BY sum(5) OVER () );

CREATE TABLE t (c INT);
INSERT t SET c=EXISTS((SELECT 1 UNION SELECT 1) ORDER BY ROW_NUMBER() OVER());

SELECT 1=ALL (SELECT 1 a UNION SELECT 1 ORDER BY SUM(a) OVER());

SELECT 1 = ALL (SELECT 1 a union SELECT 1 ORDER BY sum(a) OVER ());

SET @@SESSION.default_storage_engine='Aria';
CREATE TABLE t (numeropost INT unsigned,maxnumrep int unsigned,KEY maxnumrep (maxnumrep)) CHARSET=latin1;
CREATE TEMPORARY TABLE t (y INT);
show session variables like 'innodb_lru_scan_depth';
EXECUTE s;
SELECT 1 = ALL (SELECT 1 a union SELECT 1 ORDER BY sum(a) OVER ());

SET SESSION default_storage_engine='Aria';
CREATE TABLE t (abcdefghijk INT UNSIGNED,abcdefgh INT UNSIGNED,KEY k1 (UNSIGNED,abcdefgh)) CHARSET=latin1;
CREATE TEMPORARY TABLE t (y INT);
SHOW SESSION VARIABLES LIKE 'innodb_lru_scan_depth';
EXECUTE s;
SELECT 1=ALL (SELECT 1 a UNION SELECT 1 ORDER BY SUM(a) OVER());
