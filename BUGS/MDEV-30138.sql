SET GLOBAL aria_encrypt_tables=1;
TRUNCATE TABLE mysql.global_priv;
CREATE ROLE r1;
SET GLOBAL table_open_cache=1;
RENAME USER current_user TO abc@localhost;
