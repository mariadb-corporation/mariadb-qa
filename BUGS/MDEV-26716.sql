USE mysql;
SELECT 0 INTO OUTFILE 'a';
DROP DATABASE mysql;   # ERROR 1010 (HY000): Error dropping database (can't rmdir './mysql', errno: 39 "Directory not empty") on all versions
CREATE TABLE mysql.user (c INT);   # ERROR 1005 (HY000): Can't create table `mysql`.`user` (errno: 168 "Unknown (generic) error from engine") on 10.2 and 10.3 only, 10.4+ succeeds
GRANT PROXY ON t1 TO b@c;
