CREATE DATABASE d1;
CREATE TABLE d1.t1 (a INT, b INT);
CREATE USER fuzzu@localhost;
DENY SELECT ON d1.* TO fuzzu@localhost;
DENY INSERT ON d1.* TO fuzzu@localhost;
DENY SELECT (b) ON d1.t1 TO fuzzu@localhost;
REVOKE DENY INSERT ON d1.* FROM fuzzu@localhost;
REVOKE DENY SELECT ON d1.* FROM fuzzu@localhost;
