# mysqld options required for replay:  --skip-grant-tables=1
PREPARE s0 FROM 'SHOW GRANTS FOR unkown_user';
