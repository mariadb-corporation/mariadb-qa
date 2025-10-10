# mysqld options required for replay:  --skip-grant-tables=1
CREATE TABLE mysql.host (c INT);
FLUSH PRIVILEGES;
