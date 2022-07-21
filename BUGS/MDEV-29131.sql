CREATE ROLE r;
DROP TABLE IF EXISTS mysql.roles_mapping;
RENAME USER current_user TO 'a'@'a';
