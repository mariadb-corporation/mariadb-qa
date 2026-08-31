set sql_mode='';
GRANT PROXY ON u1@u2 TO u1@u2,u2@u2;
DELETE FROM mysql.global_priv;
FLUSH PRIVILEGES;
CREATE USER u1@u1,u1@u2;
RENAME USER u1@u2 TO u2@u2;
GRANT USAGE ON *.* TO u2@u2;
