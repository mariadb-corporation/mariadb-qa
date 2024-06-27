# mysqld options required for replay:  --skip-grant-tables=1
PREPARE s0 FROM 'SHOW GRANTS FOR unkown_user';

# mysqld options required for replay:  --skip-grant-tables=1
CREATE ROLE r1 WITH ADMIN unknown_user;
